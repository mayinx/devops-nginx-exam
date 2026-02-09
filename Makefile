# ==============================================================================
# ⚙️  CONFIG
# ==============================================================================
COMPOSE_PROJECT := mlops-exam
COMPOSE := docker compose -p $(COMPOSE_PROJECT)

# ==============================================================================
# 🚀 FULL PROJECT ORCHESTRATION (The "Production" Stack)
# ==============================================================================
start-project:
	# We use --scale instead of deploy.replicas for portability (Compose scaling)
	$(COMPOSE) up -d --build --scale api-v1=3

stop-project:
	# Shutdown the entire stack and remove internal networks
	$(COMPOSE) down

stop-all:
	# Shutdown + remove orphaned containers
	$(COMPOSE) down --remove-orphans

ps:
	# Show running services/containers for this compose project
	$(COMPOSE) ps

ps-api-v1:
	# Show only the scaled api-v1 replica containers (quick sanity-check for LB)
	$(COMPOSE) ps api-v1

# ==============================================================================
# 🔎 LOGGING / INSPECTION
# ==============================================================================
logs:
	# View real-time logs for the whole stack
	$(COMPOSE) logs -f

logs-api-v1:
	# Follow logs for the api-v1 service (shows output across replicas)
	$(COMPOSE) logs -f api-v1

logs-nginx:
	# View only Nginx logs (useful to observe rate limiting / routing)
	$(COMPOSE) logs -f nginx

# ==============================================================================
# 🧪 FULL-STACK SMOKE TESTS (via Nginx entrypoint)
# ==============================================================================
test-api:
	curl -X POST "https://localhost/predict" \
     -H "Content-Type: application/json" \
     -d '{"sentence": "Oh yeah, that was soooo cool!"}' \
	 --user admin:admin \
     --cacert ./deployments/nginx/certs/nginx.crt;

test-base:
	# Base smoke test (HTTP) – hits /predict via Nginx entrypoint
	@curl -s -X POST "http://localhost:8080/predict" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

test-burst:
	# Burst test (HTTP): send N requests via Nginx (observe LB distribution)
	# Usage: make test-burst            (defaults to 20)
	#        make test-burst N=50       (custom burst size)
	@N=$${N:-20}; \
	for i in $$(seq 1 $$N); do \
		curl -s -X POST "http://localhost:8080/predict" \
			-H "Content-Type: application/json" \
			-d '{"sentence":"I love this!"}' >/dev/null; \
	done; \
	echo "Sent $$N requests to /predict via Nginx."

# ==============================================================================
# 🔐 CERTS (TLS) – generate + verify
# ==============================================================================
gen-certs:
	# Generate self-signed certs for localhost (HTTPS milestone)
	mkdir -p deployments/nginx/certs
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout deployments/nginx/certs/nginx.key \
		-out deployments/nginx/certs/nginx.crt \
		-subj "/CN=localhost"

test-project-https:
	# HTTPS smoke test via Nginx (verifies against our self-signed cert)
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

test-http-redirect:
	# HTTP must redirect to HTTPS (301/308 + Location: https://...)
	@code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/predict); \
	loc=$$(curl -sI http://localhost:8080/predict | awk -F': ' 'tolower($$1)=="location"{print $$2}' | tr -d '\r'); \
	if ([ "$$code" = "301" ] || [ "$$code" = "308" ]) && echo "$$loc" | grep -q '^https://'; then \
		echo "PASS: HTTP -> HTTPS redirect ($$code, $$loc)"; \
	else \
		echo "FAIL: expected HTTP->HTTPS redirect, got code=$$code location=$$loc"; \
		exit 1; \
	fi

# ==============================================================================
# 🔐 BASIC AUTH – generate + verify
# ==============================================================================
gen-htpasswd:
	# Create/update Basic Auth file for Nginx (/predict protection)
	# Requires: htpasswd (package name on Ubuntu/Debian: apache2-utils)
	@mkdir -p deployments/nginx
	@htpasswd -bc deployments/nginx/.htpasswd admin admin
	@echo "OK: deployments/nginx/.htpasswd created (admin/admin)"

test-auth-required:
	# /predict must return 401 without credentials
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

test-auth-ok:
	# /predict must succeed with credentials
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

# ==============================================================================
# 🛡️ RATE LIMITING – verify (matches current Nginx default: 503)
# ==============================================================================
test-rate-limit:
	# Expect at least one 200 AND at least one 503 during a quick burst
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

# ==============================================================================
# 🧪 A/B ROUTING – verify
# ==============================================================================
test-ab-v1:
	# Default path (without debug header) hits v1
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

test-ab-v2:
	# Debug header triggers v2
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "X-Experiment-Group: debug" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

# ==============================================================================
# 🛠️ INDIVIDUAL SERVICE TESTING (API standalone, outside Compose)
# ==============================================================================
build-api-v1:
	# Build only the API v1 image
	docker build -t api-v1 -f src/api/v1/Dockerfile .

build-api-v2:
	# Build only the API v2 image
	docker build -t api-v2 -f src/api/v2/Dockerfile .

run-api-v1:
	# Run API v1 standalone (maps host 8001 -> container 8000)
	docker run --rm -d --name api-v1 -p 8001:8000 api-v1

run-api-v2:
	# Run API v2 standalone (maps host 8002 -> container 8000)
	docker run --rm -d --name api-v2 -p 8002:8000 api-v2

test-api-v1:
	# Test API v1 standalone
	curl -s -X POST "http://localhost:8001/predict" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'

test-api-v2:
	# Test API v2 standalone
	curl -s -X POST "http://localhost:8002/predict" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'

stop-api-v1:
	# Stop standalone API v1 container
	docker stop api-v1

stop-api-v2:
	# Stop standalone API v2 container
	docker stop api-v2

# ==============================================================================
# ✅ EXAM VALIDATION ENTRYPOINT
# ==============================================================================
run_tests:
	# Run the provided exam test script
	bash tests/run_tests.sh

test: run_tests