# Nginx Ingress - Reference

Manifests de referencia para labs con nginx-ingress-controller.

> **Nota:** El stack principal usa APISIX. Estos manifests son para:
> - Comparación APISIX vs Nginx
> - Labs específicos que requieran nginx
> - Referencia de configuración Ingress estándar

## Instalación

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

## Aplicar manifests

```bash
kubectl apply -f .
```

## Contenido

| Archivo | Descripción |
|---------|-------------|
| default-app.yaml | App por defecto para rutas no definidas |
| httpbin-ingress.yaml | Ingress para httpbin |
| nginx-app01.yaml | App de ejemplo 1 |
| nginx-app02.yaml | App de ejemplo 2 |
| nginx-ingress.yaml | Reglas de ingress |
| nginx-lb.yaml | LoadBalancer service |
