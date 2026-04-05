FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY krysa_pr.py .

ENTRYPOINT ["python", "-u", "krysa_pr.py"]
