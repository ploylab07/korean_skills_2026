from flask import Flask

app = Flask(__name__)


@app.route("/projects")
def projects():
    return "The projects page"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
