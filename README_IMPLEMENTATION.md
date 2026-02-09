# Implementation steps (exam log)

---

## 1. API-services: Get the 2 api containers/services running and functional

### TL;DR (setp specific): Quick reproduce (current milestone: API containers only)

```bash
make start-project
curl -s -X POST "http://localhost:8001/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'
curl -s -X POST "http://localhost:8002/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'
make stop-project
```

---

### 1.1 Create two dockerfiles (one for each api-vbersion)   

#### A) Create Dockerfile for api-v1 

In `src/api/v1/Dockerfile`:

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

#### B) Create Dockerfile for api-v2 

In `src/api/v2/Dockerfile`:

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

#### C) Call the endpoint 

```bash
curl -s -X POST "http://localhost:8001/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'
```

Should produce 

```bash
{"prediction value":"love"}`
```

### 1.4 Test api-v2

Dito - just align the commands (and port) with the requirements for api-v2:

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
    ports: # dev-only direct test for this early milestone (see README)
    - "8001:8000" # Internal port only. Public access is blocked except via Nginx.

  mlops-exam-sentiment-api-v2:
    build:
      context: .
      dockerfile: src/api/v2/Dockerfile 
    ports: # dev-only direct test for this early milestone (see README)
    - "8002:8000" # Internal port only. Public access is blocked except via Nginx.
```

>> Note: host ports are only for this early milestone. When Nginx + replicas are added, API ports will be removed (Nginx becomes the only entrypoint).

### 2.6 Add some makefile shortcuts

in `MAKEFILE:

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
# build + run both api services (docker compose up)
make start-project

# Test API v1
curl -s -X POST "http://localhost:8001/predict" \
-H "Content-Type: application/json" \
-d '{"sentence":"I love this!"}'

# Test API v2
curl -s -X POST "http://localhost:8002/predict" \
-H "Content-Type: application/json" \
-d '{"sentence":"I love this!"}'

# docker compose down
make stop-project
```

---

## 2. Reverse Proxy (basic): Add Nginx as single entrypoint and forward /predict to the APIs

### TL;DR (step specific): Quick reproduce (current milestone: Nginx reverse proxy baseline)

~~~bash
# Start stack (APIs + Nginx)
make start-project

# Call via Nginx entrypoint (HTTP for now)
curl -s -X POST "http://localhost:8080/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'

# (optional / dev-only) still possible in this milestone: direct API host ports
curl -s -X POST "http://localhost:8001/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'
curl -s -X POST "http://localhost:8002/predict" -H "Content-Type: application/json" -d '{"sentence":"I love this!"}'

make stop-project
~~~

---

### 2.1 Add Nginx Dockerfile (reverse proxy container)

Create / update `deployments/nginx/Dockerfile`:

~~~Dockerfile
# Use official Nginx image as base (includes Nginx installed + default runtime)
FROM nginx:latest

# Copy our Nginx configuration into the container image
COPY nginx.conf /etc/nginx/nginx.conf

# Nginx listens on port 80 inside the container (metadata only; host publish happens via docker-compose "ports:")
EXPOSE 80

# Run Nginx in the foreground (required for Docker containers)
CMD ["nginx", "-g", "daemon off;"]
~~~

---

### 2.2 Create the minimal Nginx config (proxy baseline)

Create / update `deployments/nginx/nginx.conf`:

~~~nginx
events {
    # Max simultaneous connections per worker process
    worker_connections 1024;
}

http {
    # Define upstream targets by docker-compose *service name* (Compose provides DNS for these names)
    # Both APIs listen on port 8000 inside their containers
    upstream api_v1 {
        server api-v1:8000;
    }

    upstream api_v2 {
        server api-v2:8000;
    }

    # HTTP server (TLS comes later; for now just validate reverse proxy works)
    server {
        listen 80;
        server_name localhost;

        # Baseline routing:
        # - For now, forward /predict to v1 by default.
        # - v2 will be used later for A/B testing based on request headers.
        location /predict {
            proxy_pass http://api-v1;

            # Forward client + scheme metadata (useful for logs and later TLS/redirect work)
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
~~~

---

### 2.3 Add Nginx to docker-compose and expose it as the entrypoint

Update `docker-compose.yml` (append the Nginx service; keep your API services as-is for now):

~~~yaml
  # 🛡️ THE GATEKEEPER: Nginx reverse proxy (single entrypoint)
  nginx:
    build:
      context: deployments/nginx/
      dockerfile: Dockerfile

    ports:
      - "8080:80" # host:container (HTTP)

    volumes:
      # Note: This overrides the config copied during image build. That's fine for dev.
      - ./deployments/nginx/nginx.conf:/etc/nginx/nginx.conf:ro

    depends_on:
      - api-v1
      - api-v2
~~~

---

### 2.4 Test reverse proxy

~~~bash
# build + run APIs + Nginx
make start-project

# Call /predict through Nginx entrypoint (HTTP)
curl -s -X POST "http://localhost:8080/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'

# stop
make stop-project
~~~

---

## 3. Load Balancing: Scale api-v1 to 3 replicas and balance requests via Nginx upstream pool

### TL;DR (step specific): Quick reproduce (current milestone: api-v1 scaled + LB via Nginx)

~~~bash
make stop-all
make start-project

# sanity: should show 3 replicas for api-v1
make ps

# call /predict via the single entrypoint (Nginx)
make test-project-base

# observe distribution across replicas (in a separate terminal)
make logs-api-v1

# optional: generate load to make distribution obvious
make test-burst N=30
~~~

---

### 3.1 Update docker-compose.yml: make api-v1 internal-only (required for scaling)

In `docker-compose.yml`:

~~~yaml
services:

  api-v1:
    build:
      context: .
      dockerfile: src/api/v1/Dockerfile
    expose:
      - "8000"

  # Note: api-v2 can remain host-exposed for dev-only debugging *for now*.
  # For final "single entrypoint" compliance, remove ports for api-v2 as well and use expose only.
  api-v2:
    build:
      context: .
      dockerfile: src/api/v2/Dockerfile
    ports:
      - "8002:8000"
~~~

Why: `ports: - "8001:8000"` cannot be used with `--scale api-v1=3` because multiple replicas cannot bind the same host port. `expose` keeps api-v1 reachable only inside the Docker network (Nginx can still reach it).

---

### 3.2 Update nginx.conf: route /predict to the api-v1 upstream pool

In `deployments/nginx/nginx.conf` (inside the `http { ... }` block):

~~~nginx
    upstream api_v1_pool {
        server api-v1:8000;
        # default strategy: round-robin
        # least_conn;
        # ip_hash;
    }

    upstream api_v2_single {
        server api-v2:8000;
    }

    server {
        listen 80;
        server_name localhost;

        location /predict {
            proxy_pass http://api_v1_pool;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
~~~

---

### 3.3 Update Makefile: scale api-v1 reliably (don’t rely on docker-compose `deploy.replicas`)

In `Makefile`:

~~~makefile
# Start full stack with Loadbalancing: scale api-v1 to 3 replicas (plain docker compose)
#
# Note: We use --scale instead of `deploy.replicas` in the docker-compose-config.   
# Reason: `deploy.replicas` is primarily a Swarm-oriented field and is not consistently applied 
# in plain `docker compose` workflows across environments - it may be ignored by plain `docker compose up` 
# in some environments - whereas --scale works consistently. 
# Using `--scale` is explicit, works with regular Compose, and keeps the exam stack portable.
start-project:
	docker compose -p mlops-exam up -d --build --scale api-v1=3
~~~


### 3.4 Test load balancing evidence (replicas + logs)

~~~bash
# start stack
make start-project

# check replicas
docker compose -p mlops-exam ps

# call endpoint via Nginx (single entrypoint)
curl -s -X POST "http://localhost:8080/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo

# follow api-v1 logs (you should see requests across api-v1-1/2/3)
docker compose -p mlops-exam logs -f api-v1

# n another terminal, generate burst traffic adn watch logs 
for i in $(seq 1 30); do
  curl -s -X POST "http://localhost:8080/predict" \
    -H "Content-Type: application/json" \
    -d '{"sentence":"I love this!"}' >/dev/null
done
~~~

---

## 4. HTTPS Security: Self-signed TLS + redirect HTTP -> HTTPS

### TL;DR (step specific): Quick reproduce (current milestone: HTTPS on Nginx)

~~~bash
# 1) Generate self-signed certs (repo-local)
make gen-certs

# 2) Start stack
make stop-all
make start-project
make ps

# 3) HTTP should redirect to HTTPS (expect 301 + Location: https://...)
curl -I http://localhost:8080/predict

# 4) HTTPS call (verify against our self-signed cert)
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo
~~~

---

### 4.1 Create a certs folder for Nginx

~~~bash
mkdir -p deployments/nginx/certs
~~~

Target files (as required by the exam):
- `deployments/nginx/certs/nginx.crt`
- `deployments/nginx/certs/nginx.key`

---

### 4.2 Generate a self-signed certificate (localhost)

~~~bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout deployments/nginx/certs/nginx.key \
  -out deployments/nginx/certs/nginx.crt \
  -subj "/CN=localhost"
~~~

---

### 4.3 Expose HTTPS + mount certs into the Nginx container

Update `docker-compose.yml` (Nginx service):

~~~yaml
  nginx:
    build:
      context: deployments/nginx/
      dockerfile: Dockerfile

    ports:
      - "8080:80"   # HTTP (used only to redirect -> HTTPS)
      - "443:443"   # HTTPS (standard TLS port)

    volumes:
      - ./deployments/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./deployments/nginx/certs:/etc/nginx/certs:ro

    depends_on:
      - api-v1
      - api-v2
~~~

---

### 4.4 Update Nginx Dockerfile to expose 443 (TLS)

Update `deployments/nginx/Dockerfile`:

~~~Dockerfile
FROM nginx:latest

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
~~~

---

### 4.5 Update nginx.conf: redirect all HTTP -> HTTPS + enable TLS termination

Update `deployments/nginx/nginx.conf`:

~~~nginx
events {
    worker_connections 1024;
}

http {

    upstream api_v1_pool {
        server api-v1:8000;
    }

    upstream api_v2_single {
        server api-v2:8000;
    }

    # HTTP: redirect everything to HTTPS
    server {
        listen 80;
        server_name localhost;

        return 301 https://$host$request_uri;
    }

    # HTTPS: terminate TLS and proxy to the API pool
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate     /etc/nginx/certs/nginx.crt;
        ssl_certificate_key /etc/nginx/certs/nginx.key;

        # SSL protocols and ciphers (lesson-aligned "modern defaults")
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location /predict {
            proxy_pass http://api_v1_pool;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
~~~

---

### 4.6 Add Makefile helpers (cert generation + HTTPS smoke test) + run tests

- Update `Makefile` to wrap the long openssl + curl --cacert commands into make targets. 
- This way TLS setup and verification are easy reproducible and consistent across reruns => less copy/paste + fewer mistakes  

~~~makefile
# Generate self-signed certs for localhost (HTTPS milestone)
gen-certs:
	mkdir -p deployments/nginx/certs
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout deployments/nginx/certs/nginx.key \
		-out deployments/nginx/certs/nginx.crt \
		-subj "/CN=localhost"

# HTTPS smoke test via Nginx (verifies against our self-signed cert)
test-project-https:
	curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

# HTTP must not serve the API directly: it must redirect to HTTPS (301/308 + Location: https://...)
test-http-redirect:
	@code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/predict); \
	loc=$$(curl -sI http://localhost:8080/predict | awk -F': ' 'tolower($$1)=="location"{print $$2}' | tr -d '\r'); \
	if ([ "$$code" = "301" ] || [ "$$code" = "308" ]) && echo "$$loc" | grep -q '^https://'; then \
		echo "PASS: HTTP -> HTTPS redirect ($$code, $$loc)"; \
	else \
		echo "FAIL: expected HTTP->HTTPS redirect, got code=$$code location=$$loc"; \
		exit 1; \
	fi

~~~



---

## 5. Access Control: Protect /predict with Basic Auth (.htpasswd)

### TL;DR (step specific): Quick reproduce (current milestone: /predict requires username+password)

~~~bash
# 1) Create credentials file (one-time)
make gen-htpasswd

# 2) Restart stack
make stop-all
make start-project

# 3) Without credentials -> must fail (401)
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'

# 4) With credentials -> must succeed (200 + JSON)
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  --user admin:admin \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo
~~~

---

### 5.1 Generate the `.htpasswd` file (credentials store for Nginx)

Create / update `deployments/nginx/.htpasswd`:

~~~bash
# Creates the .htpasswd-file (-c) and adds user "admin"
# When prompted, enter a password (e.g. 'admin' for simplicity/demo)
htpasswd -c deployments/nginx/.htpasswd admin
~~~

If we would add more users later, we would do that without `-c` (since the file already exists):
~~~bash
htpasswd deployments/nginx/.htpasswd username
~~~

---

### 5.2 Update docker-compose.yml to mount `.htpasswd` into the Nginx container

Update `docker-compose.yml` (Nginx service volumes):

~~~yaml
    volumes:
      - ./deployments/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./deployments/nginx/certs:/etc/nginx/certs:ro
      - ./deployments/nginx/.htpasswd:/etc/nginx/.htpasswd:ro
~~~

---

### 5.3 (Optional) Also COPY certs + .htpasswd into the Nginx image (standalone / prod-like)

> Why (optional)?  
> With bind-mounts, Nginx reads config/certs/auth files directly from the host at runtime (fast iteration).  
> With `COPY`, those files are baked into the image, so the Nginx container can run **standalone** (no compose file / no host mounts required).  
> If you keep BOTH: the bind-mounts in `docker-compose.yml` will **override** the baked-in files at the same paths.

Update `deployments/nginx/Dockerfile` (add the COPY lines):

~~~Dockerfile
FROM nginx:latest

# Optional: bake nginx,config certs + htpasswd into the image as defaults (useful if the image is run without docker-compose)
# (docker-compose bind-mounts override these at runtime, but this makes the image portable/standalone)
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/
COPY .htpasswd /etc/nginx/.htpasswd

EXPOSE 80
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]
~~~

---


### 5.4 Enable Basic Auth on `/predict` in nginx.conf

Update `deployments/nginx/nginx.conf` (inside the HTTPS server’s `location /predict` block):

~~~nginx
location /predict {
    # Basic Auth: protect this endpoint with username/password
    auth_basic "API Access Protected";
    auth_basic_user_file /etc/nginx/.htpasswd;

    proxy_pass http://api_v1_pool;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
~~~

---

### 5.5 Add Makefile helpers (generate credentials + smoke tests) + run tests

Update `Makefile`:

~~~makefile
# Create/update Basic Auth file for Nginx (/predict protection)
# Requires: htpasswd (package name on Ubuntu/Debian: apache2-utils)
gen-htpasswd:
	@mkdir -p deployments/nginx
	@htpasswd -bc deployments/nginx/.htpasswd admin admin
	@echo "OK: deployments/nginx/.htpasswd created (admin/admin)"

# Smoke test: /predict must return 401 without credentials
test-auth-required:
	@code=$$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'); \
	if [ "$$code" = "401" ]; then \
		echo "PASS: auth required (401)"; \
	else \
		echo "FAIL: expected 401, got $$code"; \
		exit 1; \
	fi

# Smoke test: /predict must succeed with credentials
test-auth-ok:
	@code=$$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'); \
	if [ "$$code" = "200" ]; then \
		echo "PASS: auth accepted (200)"; \
	else \
		echo "FAIL: expected 200, got $$code"; \
		exit 1; \
	fi
~~~


---

## 6. Rate Limiting: Protect /predict from overload (10 req/s per IP)

### TL;DR (step specific): Quick reproduce (current milestone: bursty calls trigger 503)

~~~bash
# Restart stack (after config changes)
make stop-all
make start-project

# 1) Authenticated burst test (expect some 200s and some 503s once limit kicks in)
make test-rate-limit

# 2) Inspect Nginx logs (should show "limiting requests" lines)
make logs-nginx
~~~

---

### 6.1 Add rate limit zone (http block) + apply it to /predict (location block)

Update `deployments/nginx/nginx.conf`:

~~~nginx
http {
    # RATE LIMITING: track request rate per client IP
    # - zone name: apilimit
    # - memory: 10m
    # - rate: 10 requests/second per IP
    limit_req_zone $binary_remote_addr zone=apilimit:10m rate=10r/s;

    # ... keep upstreams + servers as-is ...

    server {
        listen 443 ssl;
        server_name localhost;

        # ... keep TLS settings as-is ...

        location /predict {
            # Basic Auth (already implemented)
            auth_basic "API Access Protected";
            auth_basic_user_file /etc/nginx/.htpasswd;

            # Apply rate limiting to this endpoint only
            # burst=5 allows short spikes; requests beyond that are rejected (503)
            limit_req zone=apilimit burst=5 nodelay;

            proxy_pass http://api_v1_pool;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
~~~

---

### 6.2 Add Makefile helper: burst test (prints a simple pass/fail summary) + run tests

Update `Makefile`:

~~~makefile
# Burst test: hit /predict multiple times quickly.
# Expectation: at least one 200 AND at least one 503 once rate limiting triggers.
test-rate-limit:
	@ok=0; limited=0; \
	for i in $$(seq 1 20); do \
		code=$$(curl -s -o /dev/null -w "%{http_code}" \
			-X POST "https://localhost/predict" \
			--cacert ./deployments/nginx/certs/nginx.crt \
			--user admin:admin \
			-H "Content-Type: application/json" \
			-d '{"sentence":"I love this!"}'); \
		[ "$$code" = "200" ] && ok=1; \
		[ "$$code" = "503" ] && limited=1; \
	done; \
	if [ $$ok -eq 1 ] && [ $$limited -eq 1 ]; then \
		echo "PASS: rate limiting active (saw 200 and 503)"; \
	else \
		echo "FAIL: expected both 200 and 503 (ok=$$ok limited=$$limited)"; \
		exit 1; \
	fi
~~~

---


---

## 7. A/B Testing: Route to api-v2 only when `X-Experiment-Group: debug` is present

### TL;DR (step specific): Quick reproduce (current milestone: header-based routing)

~~~bash
# Start stack
make start-project

# Default (no header) -> api-v1 (should behave like "normal" response)
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  --user admin:admin \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo

# With header -> api-v2 ("debug" response)
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  --user admin:admin \
  -H "X-Experiment-Group: debug" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo

# Watch routing behavior in logs (optional)
docker compose -p mlops-exam logs -f api-v1
docker compose -p mlops-exam logs -f api-v2
docker compose -p mlops-exam logs -f nginx

make stop-project
~~~

---

### 7.1 Add header → upstream routing with `map` (nginx.conf)

Update `deployments/nginx/nginx.conf`:

~~~nginx
events {
    worker_connections 1024;
}

http {
    # RATE LIMITING (already implemented)
    limit_req_zone $binary_remote_addr zone=apilimit:10m rate=10r/s;

    # LOAD BALANCING / UPSTREAMS (already implemented)
    upstream api_v1_pool {
        server api-v1:8000;  # Compose DNS -> balances across all api-v1 replicas
    }

    upstream api_v2_single {
        server api-v2:8000;  # Single debug service
    }

    # A/B ROUTING/TESTING (step 1/2): choose upstream (and thus api-v) based on request header 
    # - default -> api_v1_pool 
    # - debug   -> If client sends: 'X-Experiment-Group: debug' => route to api_v2_single   
    #   (Header: X-Experiment-Group -> variable: $http_x_experiment_group)
    map $http_x_experiment_group $predict_upstream {
        default  api_v1_pool;
        debug    api_v2_single;
    }

    # HTTP -> HTTPS redirect (already implemented)
    server {
        listen 80;
        server_name localhost;
        return 301 https://$host$request_uri;
    }

    # HTTPS entrypoint (already implemented)
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate /etc/nginx/certs/nginx.crt;
        ssl_certificate_key /etc/nginx/certs/nginx.key;

        # /predict is protected + rate-limited (already implemented)
        location /predict {
            auth_basic "API Access Protected";
            auth_basic_user_file /etc/nginx/.htpasswd;

            limit_req zone=apilimit burst=5 nodelay;

            # A/B-routing (step 2/2): 
            # A/B routing based on map result - the A/B routing decision 
            # happens here (value comes from `map` above)           
            proxy_pass http://$predict_upstream;
^
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
~~~

---

### 7.2 Restart + validate routing

~~~bash
make stop-all
make start-project

# Default route (no header) -> api-v1
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  --user admin:admin \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo

# Debug route (header present) -> api-v2
curl -s -X POST "https://localhost/predict" \
  --cacert ./deployments/nginx/certs/nginx.crt \
  --user admin:admin \
  -H "X-Experiment-Group: debug" \
  -H "Content-Type: application/json" \
  -d '{"sentence":"I love this!"}'; echo

# Confirm by watching logs in parallel (two terminals)
docker compose -p mlops-exam logs -f api-v1
docker compose -p mlops-exam logs -f api-v2
~~~

### 7.3 Optional Makefile helpers (two quick A/B smoke tests)

```bash
# Smoke test: default path (without debug header) hits v1 (no experiment header)
test-ab-v1:
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

# Smoke test: debug header triggers v2 (debug path)
test-ab-v2:
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "X-Experiment-Group: debug" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo
```

---

## 8. Monitoring (Bonus): Prometheus + Grafana for Nginx metrics (stub_status + exporter)

### TL;DR (step specific): Quick reproduce (current milestone: metrics visible + Grafana reachable)

~~~bash
# Start the full stack
make start-project

# Check exporter is up (should return Prometheus-formatted metrics)
curl -s http://localhost:9113/metrics | head

# Open UIs:
# - Prometheus: http://localhost:9090
# - Grafana:    http://localhost:3000  (login: admin / admin)

# Stop
make stop-all
~~~

> Note: We intentionally scrape Nginx status over **internal HTTP** (inside the Compose network) to avoid HTTPS + self-signed certificate headaches for the exporter.

---

### 8.1 Add an internal-only Nginx status endpoint (nginx.conf)

Update `deployments/nginx/nginx.conf`:

~~~nginx
events {
    worker_connections 1024;
}

http {
    # RATE LIMITING: define shared limit zone (step 6)
    limit_req_zone $binary_remote_addr zone=apilimit:10m rate=10r/s;

    # A/B ROUTING: choose upstream based on header (step 7)
    map $http_x_experiment_group $predict_upstream {
        default  api_v1_pool;
        debug    api_v2_single;
    }

    upstream api_v1_pool {
        server api-v1:8000;
    }

    upstream api_v2_single {
        server api-v2:8000;
    }

    # HTTP (host port 8080): redirect-only
    server {
        listen 80;
        server_name localhost;
        return 301 https://$host$request_uri;
    }

    # HTTPS (host port 443): real API entrypoint
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate     /etc/nginx/certs/nginx.crt;
        ssl_certificate_key /etc/nginx/certs/nginx.key;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location /predict {
            # Basic Auth (step 5)
            auth_basic "API Access Protected";
            auth_basic_user_file /etc/nginx/.htpasswd;

            # Rate limiting (step 6)
            limit_req zone=apilimit burst=5 nodelay;

            # A/B routing (step 7)
            proxy_pass http://$predict_upstream;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # INTERNAL METRICS ENDPOINT (not published to host)
    # - separate listener to avoid the HTTP->HTTPS redirect loop for the exporter
    # - allow only loopback + Docker private ranges (portable across Compose subnets)
    server {
        listen 8081;
        server_name nginx;

        location /nginx_status {
            stub_status on;
            access_log off;

            allow 127.0.0.1;
            allow 172.16.0.0/12;
            allow 192.168.0.0/16;
            deny all;
        }
    }
}
~~~

---

### 8.2 Add services: nginx_exporter + prometheus + grafana (docker-compose.yml)

Update `docker-compose.yml` (append these services; keep existing ones unchanged):

~~~yaml
services:
  # NOTE: We scale with `docker compose ... --scale api-v1=3` (portable Compose)
  # instead of `deploy.replicas` (Swarm mode feature; may be ignored by plain `docker compose`).
  api-v1:
    build:
      context: .
      dockerfile: src/api/v1/Dockerfile
    expose:
      - "8000"

  api-v2:
    build:
      context: .
      dockerfile: src/api/v2/Dockerfile
    expose:
      - "8000"

  nginx:
    build:
      context: deployments/nginx/
      dockerfile: Dockerfile
    ports:
      - "8080:80"   # HTTP (redirect-only)
      - "443:443"   # HTTPS entrypoint
    volumes:
      - ./deployments/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./deployments/nginx/certs:/etc/nginx/certs:ro
      - ./deployments/nginx/.htpasswd:/etc/nginx/.htpasswd:ro
    depends_on:
      - api-v1
      - api-v2

  nginx_exporter:
    image: nginx/nginx-prometheus-exporter:latest
    ports:
      - "9113:9113" # expose exporter to host for quick checking
    depends_on:
      - nginx
    command:
      - "--nginx.scrape-uri=http://nginx:8081/nginx_status"

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./deployments/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    depends_on:
      - nginx_exporter

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin

volumes:
  prometheus_data:
  grafana_data:
~~~

---

### 8.3 Add Prometheus scrape config (prometheus.yml)

Create `deployments/prometheus/prometheus.yml`:

~~~yaml
global:
  scrape_interval: 3s

scrape_configs:
  - job_name: "nginx-exporter"
    static_configs:
      - targets: ["nginx_exporter:9113"]
~~~

---

### 8.4 Start + verify metrics

~~~bash
make stop-all
make start-project

# Exporter metrics should be readable
curl -s http://localhost:9113/metrics | head

# Prometheus UI: http://localhost:9090
# Grafana UI:    http://localhost:3000  (admin/admin)
~~~

---

### 8.5 Grafana setup (minimal)

1) Open Grafana → login `admin / admin`  
2) Connections → Data sources → Add data source → **Prometheus**  
3) URL: `http://prometheus:9090` → **Save & Test**  
4) Optional: Import a ready dashboard:
   - Dashboards → New → Import → enter dashboard ID `12708` (Nginx exporter) → Import

---
 

### 8.6 Verify Monitoring end-to-end

```bash 
# 1) Generate some traffic (hits both auth + AB + rate limit paths)
make test-ab-v1
make test-ab-v2
make test-rate-limit

# Optional: create a short burst to see rate-limit logs (some 503s expected)
for i in {1..30}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST "https://localhost/predict" \
    --cacert ./deployments/nginx/certs/nginx.crt \
    --user admin:admin \
    -H "Content-Type: application/json" \
    -d '{"sentence":"Oh yeah, that was soooo cool!"}' &
done; wait

# 2) Check exporter metrics directly (host)
curl -s http://localhost:9113/metrics | head

# 3) Prometheus: confirm targets are UP
# Open in browser: http://localhost:9090/targets

# 4) Quick Prometheus query ideas (browser -> Graph/Query):
# - nginx_up
# - nginx_connections_active
# - rate(nginx_http_requests_total[1m])

# 5) Grafana: open UI, add Prometheus datasource, import dashboard 12708
# http://localhost:3000  (admin / admin)
```

---
