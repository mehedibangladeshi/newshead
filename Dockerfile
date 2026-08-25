FROM python:3.12-slim

# The container runs as root and bind-mounts the host repo (see
# scrape.yml's `docker run -v "$PWD:/app"`) - without this, Python's
# auto-generated __pycache__/*.pyc files end up root-owned on the host,
# which the self-hosted runner's non-root user then can't clean up on the
# next checkout's `git clean -ffdx` (permission denied unlinking files in a
# root-owned directory), forcing a full repo recreate that can itself fail
# the same way.
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY scraper/requirements.txt scraper/requirements.txt
RUN pip install --no-cache-dir -r scraper/requirements.txt

COPY . .

CMD ["python", "scripts/generate.py"]
