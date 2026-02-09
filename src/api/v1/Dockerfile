# Start from the official Python 3.12 “slim” base image (Debian-based) 
# — provides the OS + Python runtime we build on
FROM python:3.12-slim

# Set the working directory inside the image to /app:
# - Subsequent instructions run relative to this directory 
#   (e.g., `COPY ... .` -> /app, `RUN ...` executes in /app).
# - When the container starts, this is the default "current directory" 
#   (so `uvicorn main:app` can import /app/main.py).
# - Docker creates /app automatically if it doesn't exist.
WORKDIR /app

# Copy dependency list from repo into the image
# (Path is relative to the build context, 
# repo root when we build with `-f ... .`)
COPY src/api/requirements.txt .

# Install Python dependencies into the image
# --no-cache-dir keeps the image smaller (no pip download cache stored in the layer)
RUN pip install --no-cache-dir -r requirements.txt

# Copy the trained model file into the image
# The app will load it from /app/model.joblib (because WORKDIR=/app)
COPY model/model.joblib .

# Copy the FastAPI app entrypoint into the image (main.py -> /app/main.py)
COPY src/api/v1/main.py .

# Metadata/documentation for Docker & tooling
# - Declare that the app inside the container listens on TCP port 8000.
# - this metadata/docu does NOT open/publish the port to the host.
# - To reach it from our machine we still need `docker run -p HOST_PORT:8000 ...` 
#   or a compose `ports:` mapping.
EXPOSE 8000

# Container startup command:
# - Run the ASGI server "uvicorn" to serve the FastAPI app.
# - "main:app" = import the object named `app` (FastApi-Instance) from the Python module `main` (i.e., /app/main.py).
# - "--host 0.0.0.0" binds to all network interfaces so other containers / the host (via port mapping) can reach it.
#   (Binding to 127.0.0.1 would make it reachable only from inside the container.)
# - "--port 8000" is the internal container port the app listens on.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]