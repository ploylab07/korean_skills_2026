FROM python:3.8-slim-bookworm

WORKDIR /app

RUN pip install --no-cache-dir flask==2.3.3

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
