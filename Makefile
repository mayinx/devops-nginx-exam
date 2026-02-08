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
start-project:
	docker compose -p mlops-exam up -d --build

# Shutdown the entire stack and remove internal networks
stop-project:
	docker compose -p mlops-exam down

# Shutdown ...
stop-all:
	docker compose -p mlops-exam down --remove-orphans



# 📋 View real-time logs for the whole stack (Handy for debugging!)
logs:
	docker compose -p mlops-exam logs -f

# 🛡️ View only Nginx logs (To see Rate Limiting in action)
logs-nginx:
	docker logs -f nginx_revproxy