# Copilot local instructions

## MCP server shortcuts

- name: mcp
  description: Use the cluster Service or Ingress for cryptophys MCP and access it via mcp.cryptophys.work (update Cloudflare to point to the Service/Ingress external IP or hostname).
  access: Ensure the Kubernetes Service is of type LoadBalancer or exposed via an Ingress controller; do NOT use kubectl port-forward.

Usage:
1. Confirm the Service name (e.g. service/cryptophys-mcp-http) and its port (e.g. 80 or 8080).
2. Expose it with a LoadBalancer or Ingress and obtain the external IP/hostname.
3. Update Cloudflare DNS for mcp.cryptophys.work to point to that IP/hostname.
4. Access https://mcp.cryptophys.work in your browser or use it in Copilot requests.

(If Service name or ports differ, replace service/cryptophys-mcp-http and ports accordingly.)
