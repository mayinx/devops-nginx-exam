# deployments/nginx/Dockerfile
# Use official Nginx image as base (includes Nginx installed + default runtime)
FROM nginx:latest

# Copy our Nginx configuration into the container image
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/ 
# COPY .htpasswd /etc/nginx/.htpasswd

# Nginx listens on port 80 inside the container (metadata only; host publish happens via docker-compose "ports:")
EXPOSE 80
EXPOSE 443

# Run Nginx in the foreground (required for Docker containers)
CMD ["nginx", "-g", "daemon off;"]