# README_IMPLEMENTATION.md — Implementation steps (exam log)

## 1. API-services: Get the 2 api containers/services running and functional

### TL;DR (setp specific): Quick reproduce (current milestone: API containers only)
make start-project
curl -s -X POST "http://localhost:8001/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'
curl -s -X POST "http://localhost:8002/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'
make stop-project

### 1.1 Create two dockerfiles (one for each api-vbersion)   

#### A) src/api/v1/Dockerfile:

```Dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY src/api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY model/model.joblib .
COPY src/api/v1/main.py . 

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

#### B) src/api/v2/Dockerfile:

```Dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY src/api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY model/model.joblib .
COPY src/api/v2/main.py . 

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```


### 1.2 List api-requirements

in `mlops-nginx-exam-2/src/api/requirements.txt`:

```bash
joblib==1.5.1
numpy==2.2.6
fastapi==0.115.12
scikit-learn==1.6.1 # To use our model
uvicorn==0.34.3 # To launch our API
```

### 1.3 Test api-v1

#### A) Build image from Dockerfile 

```bash
# Build the repo image from repo root (i.e. behold the trailing dot): 
# -f src/api/v1/Dockerfile = where the Dockerfile lives
# . = repo root build context, so Docker can access model/ 
#    and src/api/ from within the Dockerfile...
 docker build -t api-v1 -f src/api/v1/Dockerfile .
 ```

#### B) Run the container

```bash
docker run --rm -d --name api-v1 -p 8001:8000 api-v1  
```

##### C) Call the endpoint 

```bash
curl -s -X POST "http://localhost:8001/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'
```

Should produce 

```bash
{"prediction value":"love"}`
```

### 1,4 Test api-v2

Dito - just align the commands (and port) with the requriemnents for api-v2:

```bash
# Build only the API image
docker build -t api-v2 -f src/api/v2/Dockerfile .	

# Run the API as a standalone container (maps port 8000 to 8000)
docker run --rm -d --name api-v2 -p 8002:8000 api-v2

# Test API
curl -s -X POST "http://localhost:8002/predict" \
-H "Content-Type: application/json" \
-d '{"sentence":"I love this!"}'
```

### 1.5 Add composer config for the two api-services

```bash
services:

  # 🧠 THE ENGINE: FastAPI application
  # feat(api): containerize v1 and v2 services and validate /predict
  mlops-exam-sentiment-api-v1:
    build:
      context: .
      dockerfile: src/api/v1/Dockerfile 
    ports: # dev-only direct test (see README)
    - "8001:8000" # Internal port only. Public access is blocked except via Nginx.

  mlops-exam-sentiment-api-v2:
    build:
      context: .
      dockerfile: src/api/v2/Dockerfile 
    ports: # dev-only direct test (see README)
    - "8002:8000" # Internal port only. Public access is blocked except via Nginx.
```

>> Note: host ports are only for this early milestone. When Nginx + replicas are added, API ports will be removed (Nginx becomes the only entrypoint).

### 2.6 Add some makefile shortcuts

```makefile
# Launch everything: 3x API replicas, Nginx, Exporter, Prometheus, Grafana
start-project:
	docker compose -p mlops-exam up -d --build

# Shutdown the entire stack and remove internal networks
stop-project:
	docker compose -p mlops-exam down
```

### 1.7 Test composer 

```bash
# build + run both api sevrices
make start-project

# Test API v1
curl -s -X POST "http://localhost:8001/predict" \
-H "Content-Type: application/json" \
-d '{"sentence":"I love this!"}'

# Test API v2
curl -s -X POST "http://localhost:8002/predict" \
-H "Content-Type: application/json" \
-d '{"sentence":"I love this!"}'

# build + run both api services
make stop-project
```

