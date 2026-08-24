FROM python:3.12-slim

WORKDIR /app

COPY scraper/requirements.txt scraper/requirements.txt
RUN pip install --no-cache-dir -r scraper/requirements.txt

COPY . .

CMD ["python", "scripts/generate.py"]
