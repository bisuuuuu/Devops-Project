provider "aws" {
  region = var.aws_region
}

# -----------------------------
# VPC
# -----------------------------
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "devops2tier-vpc"
  }
}

# -----------------------------
# Public Subnet
# -----------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-north-1a"

  tags = {
    Name = "public-subnet"
  }
}

# -----------------------------
# Internet Gateway
# -----------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "devops2tier-igw"
  }
}

# -----------------------------
# Route Table for Public Subnet
# -----------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg"
  }
}

resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Allow backend API access"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

# -----------------------------
# Frontend EC2
# -----------------------------
resource "aws_instance" "frontend" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  security_groups        = [aws_security_group.frontend_sg.id]
  key_name               = var.key_name

  user_data = <<-EOF
#!/bin/bash
apt update -y
apt install -y docker.io
systemctl start docker

# Create index.html
cat <<EOT > /home/ubuntu/index.html
<!DOCTYPE html>
<html>
<head>
    <title>DevOps Login</title>
    <style>
        body { background-color: #282c34; color: #61dafb; font-family: Arial, sans-serif; text-align: center; }
        form { margin-top: 30px; background: #333; padding: 25px; border-radius: 8px; display: inline-block; text-align: left; width: 300px; }
        .form-header { font-size: 22px; font-weight: bold; text-align: center; margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; }
        input[type="email"], input[type="password"] { width: 100%; padding: 8px; border: 1px solid #61dafb; border-radius: 4px; margin-bottom: 15px; background: #222; color: #61dafb; }
        input[type="submit"] { width: 100%; background: #61dafb; border: none; padding: 10px; cursor: pointer; color: #000; font-weight: bold; margin-top: 5px; }
        .forgot { text-align: center; margin-top: 10px; font-size: 12px; color: #61dafb; cursor: pointer; }
        .success { margin-top: 15px; text-align: center; color: limegreen; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Welcome here ! Biswa this side</h1>
    <form id="loginForm">
        <div class="form-header">Login</div>
        <label for="email">Email:</label>
        <input type="email" id="email" name="email" required>
        <label for="password">Password:</label>
        <input type="password" id="password" name="password" required>
        <input type="submit" value="Submit">
        <div class="forgot">Forgot Password?</div>
        <div id="result" class="success"></div>
    </form>
    <script>
        document.getElementById("loginForm").addEventListener("submit", async function(e) {
            e.preventDefault();
            const email = document.getElementById("email").value;
            const password = document.getElementById("password").value;
            const response = await fetch("http://${aws_instance.backend.public_ip}:5000/save", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ email, password })
            });
            const result = await response.json();
            document.getElementById("result").innerText = result.message;
        });
    </script>
</body>
</html>
EOT

docker run -d -p 80:80 --name frontend -v /home/ubuntu/index.html:/usr/share/nginx/html/index.html nginx
EOF
}

# -----------------------------
# Backend EC2
# -----------------------------
resource "aws_instance" "backend" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.backend_sg.id]
  key_name                    = var.key_name

  user_data = <<-EOF
#!/bin/bash
exec > >(tee /var/log/user_data.log|logger -t user-data ) 2>&1
set -x

apt update -y
apt install -y docker.io
systemctl start docker

mkdir -p /home/ubuntu/backend
cd /home/ubuntu/backend

# Create Flask backend app
cat <<EOT > app.py
from flask import Flask, request, jsonify
from flask_cors import CORS
from pymongo import MongoClient

app = Flask(__name__)
CORS(app)

print("🚀 Starting Flask app and connecting to MongoDB Atlas...")
client = MongoClient("mongodb+srv://dbuser:dbpass123@cluster0.i3gcqrs.mongodb.net/devopsdb?retryWrites=true&w=majority")
db = client["devopsdb"]
users = db["users"]

@app.route('/save', methods=['POST'])
def save():
    data = request.json
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return jsonify({"message": "Email and Password required"}), 400

    users.insert_one({"email": email, "password": password})
    print(f"✅ Inserted user: {email}")
    return jsonify({"message": "Login data stored successfully!"})

if __name__ == '__main__':
    print("✅ Flask backend running on port 5000")
    app.run(host='0.0.0.0', port=5000)
EOT

# Create Dockerfile
cat <<EOT > Dockerfile
FROM python:3.9
WORKDIR /app
COPY . .
RUN pip install flask flask-cors pymongo
CMD ["python", "app.py"]
EOT

docker build -t biswaa18/backend:1.0 .
docker run -d --name backend -p 5000:5000 biswaa18/backend:1.0

# Log container status
docker ps
docker logs -f backend > /var/log/backend.log 2>&1 &
EOF
}
