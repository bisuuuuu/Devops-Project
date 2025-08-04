from flask import Flask, request, jsonify
from flask_cors import CORS
from pymongo import MongoClient

app = Flask(__name__)
CORS(app)

# MongoDB Atlas Connection
try:
    client = MongoClient("mongodb+srv://dbuser:dbpass123@cluster0.i3gcqrs.mongodb.net/devopsdb?retryWrites=true&w=majority&appName=Cluster0")
    db = client["devopsdb"]
    users = db["users"]
    print("✅ Connected to MongoDB Atlas successfully")
except Exception as e:
    print("❌ MongoDB Connection Failed:", e)

@app.route('/save', methods=['POST'])
def save():
    data = request.json
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return jsonify({"message": "Email and Password required"}), 400

    users.insert_one({"email": email, "password": password})
    return jsonify({"message": "Login data stored successfully!"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)

