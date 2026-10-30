import os

import psycopg2
from flask import Flask

app = Flask(__name__)


def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        dbname=os.getenv("POSTGRES_DB", "app"),
        user=os.getenv("POSTGRES_USER", "app"),
        password=os.getenv("POSTGRES_PASSWORD", "app"),
        connect_timeout=5,
    )


@app.route("/health")
def health():
    return "ok\n"


@app.route("/")
def index():
    connection = get_connection()
    try:
        with connection, connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                "id SERIAL PRIMARY KEY, visited_at TIMESTAMP DEFAULT now())"
            )
            cursor.execute("INSERT INTO visits DEFAULT VALUES")
            cursor.execute("SELECT count(*) FROM visits")
            count = cursor.fetchone()[0]
    finally:
        connection.close()
    return f"Hello from Docker, Q! Visits: {count}\n"
