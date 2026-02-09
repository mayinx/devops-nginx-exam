run-project:
	# run project
	@echo "Grafana UI: http://localhost:3000"

test-api:
	curl -X POST "https://localhost/predict" \
     -H "Content-Type: application/json" \
     -d '{"sentence": "Oh yeah, that was soooo cool!"}' \
	 --user admin:admin \
     --cacert ./deployments/nginx/certs/nginx.crt;

# ==============================================================================
# 🛠️ INDIVIDUAL SERVICE TESTING (Use these to debug the API alone)
# ==============================================================================

# Build only the API image
build-api-v1:
	docker build -t api-v1 -f src/api/v1/Dockerfile .
build-api-v2:
	docker build -t api-v2 -f src/api/v2/Dockerfile .	

# Run the API as a standalone container (maps port 8000 to 8000)
run-api-v1:
	docker run --rm -d --name api-v1 -p 8001:8000 api-v1
run-api-v2:
	docker run --rm -d --name api-v2 -p 8002:8000 api-v2

# Test APIs
test-api-v1:
	curl -s -X POST "http://localhost:8001/predict" \
	-H "Content-Type: application/json" \
	-d '{"sentence":"I love this!"}'
test-api-v2:
	curl -s -X POST "http://localhost:8002/predict" \
	-H "Content-Type: application/json" \
	-d '{"sentence":"I love this!"}'

# Kill the standalone API container
stop-api-v1:
	docker stop api-v1 
stop-api-v2:
	docker stop api-v2 

# ==============================================================================
# 🚀 FULL PROJECT ORCHESTRATION (The "Production" Stack)
# ==============================================================================

# Launch everything: 3x API replicas, Nginx, Exporter, Prometheus, Grafana
# start-project:
# 	docker compose -p mlops-exam up -d --build
# TODO: We use --scale here instead of the replcias-option in docker-compose, 
# since using replicas alone is risky when it comes to portability
start-project:
	docker compose -p mlops-exam up -d --build --scale api-v1=3

# Shutdown the entire stack and remove internal networks
stop-project:
	docker compose -p mlops-exam down

# Shutdown ...
stop-all:
	docker compose -p mlops-exam down --remove-orphans


### inspecting

# 📋 View real-time logs for the whole stack (Handy for debugging!)
logs:
	docker compose -p mlops-exam logs -f

# 🔎 Follow logs for the api-v1 service (shows output across replicas)
logs-api-v1:
	docker compose -p mlops-exam logs -f api-v1

# 🛡️ View only Nginx logs (To see Rate Limiting in action)
logs-nginx:
	docker compose -p mlops-exam logs -f nginx


# 📋 Show running services/containers for this compose project
ps:
	docker compose -p mlops-exam ps

# 📋 Show only the scaled api-v1 replica containers (quick sanity-check for LB)
ps-api-v1:
	docker compose -p mlops-exam ps api-v1


# ## testing 	

# 🧪 Base smoke test: hit /predict via Nginx entrypoint (HTTP)
test-base:
	@curl -s -X POST "http://localhost:8080/predict" \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

# 🧪 Burst test: send N requests via Nginx (useful to observe LB distribution)
# Usage: make test-burst            (defaults to 20)
#        make test-burst N=50       (custom burst size)
test-burst:
	@N=$${N:-20}; \
	for i in $$(seq 1 $$N); do \
		curl -s -X POST "http://localhost:8080/predict" \
			-H "Content-Type: application/json" \
			-d '{"sentence":"I love this!"}' >/dev/null; \
	done; \
	echo "Sent $$N requests to /predict via Nginx."



## certs handling + testing
#  to wrap the long openssl + curl --cacert commands into make targets. 
#  TLS setup and verification become easy reproducible and consistent across reruns 
# => less copy/paste + fewer mistakes  


# Generate self-signed certs for localhost (HTTPS milestone)
gen-certs:
	mkdir -p deployments/nginx/certs
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout deployments/nginx/certs/nginx.key \
		-out deployments/nginx/certs/nginx.crt \
		-subj "/CN=localhost"

# HTTPS smoke test via Nginx (verifies against our self-signed cert)
test-project-https:
	@curl -s -X POST "https://localhost/predict" \
		--cacert ./deployments/nginx/certs/nginx.crt \
		--user admin:admin \
		-H "Content-Type: application/json" \
		-d '{"sentence":"I love this!"}'; echo

# HTTP must not serve the API directly: it must redirect to HTTPS (301/308 + Location: https://...)
# Pass criteria:
# - Status code is 301 or 308
# - Location header starts with https://
# What this does:
# - curl #1: fetch only the HTTP status code (no body) into `code`
# - curl #2: fetch headers only and extract the Location header into `loc`
# - PASS if code is 301/308 AND Location starts with https://, else FAIL (exit 1)
# Notes:
# - awk = small CLI text parser; here it splits header lines on ": " and prints the Location value (URL) only
# - $$ is required in Makefiles to pass a literal $ to the shell/awk
# - tr -d '\r' removes CR from HTTP headers (CRLF) so matching works reliably
test-http-redirect:
	@code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/predict); \
	loc=$$(curl -sI http://localhost:8080/predict | awk -F': ' 'tolower($$1)=="location"{print $$2}' | tr -d '\r'); \
	if ([ "$$code" = "301" ] || [ "$$code" = "308" ]) && echo "$$loc" | grep -q '^https://'; then \
		echo "PASS: HTTP -> HTTPS redirect ($$code, $$loc)"; \
	else \
		echo "FAIL: expected HTTP->HTTPS redirect, got code=$$code location=$$loc"; \
		exit 1; \
	fi		


## auth related


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

## A/B smoke tests

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
	