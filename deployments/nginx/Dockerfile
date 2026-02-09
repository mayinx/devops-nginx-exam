# deployments/nginx/Dockerfile
# Use official Nginx image as base (includes Nginx installed + default runtime)
FROM nginx:latest

# Copy Nginx config, certs + auth into the container image
#    
# Bake config + secrets into the image as a *default* so the container can run standalone
# (e.g., if someone runs the image without docker-compose or without the volume mounts in docker compose).
# Note: In our docker-compose.yml we also bind-mount these same paths for dev/exam iteration.
# When the bind-mounts are enabled, they OVERRIDE these baked-in files at runtime.
# We keep both strategies for the mentioned reasons - and because the lesson used both strategies simultaniously as well.
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/ 
COPY .htpasswd /etc/nginx/.htpasswd

# Nginx listens on port 80 inside the container (metadata only; host publish happens via docker-compose "ports:")
EXPOSE 80
EXPOSE 443

# Run Nginx in the foreground (required for Docker containers)
CMD ["nginx", "-g", "daemon off;"]