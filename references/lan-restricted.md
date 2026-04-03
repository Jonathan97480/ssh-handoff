# LAN-restricted browser terminal pattern

Use this pattern when the user wants to open the temporary terminal from another machine on the same local network.

## Safe flow

1. Ask the user for their local IP address.
2. Launch the web terminal on the server LAN IP with temporary credentials.
3. Show an allow rule restricted to that single client IP and that single port.
4. After the task, show the exact delete rule.

## Example

If the server is `192.168.1.28`, the client is `192.168.1.30`, and ttyd chose port `54945`:

Allow:

```bash
sudo ufw allow from 192.168.1.30 to any port 54945 proto tcp
```

Remove later:

```bash
sudo ufw delete allow from 192.168.1.30 to any port 54945 proto tcp
```

## Guardrails

- Restrict to one IP only.
- Do not open `Anywhere` for the ttyd port.
- Keep temporary credentials enabled.
- Remove the rule after use.
- Do not create external tunnels or public reverse proxy exposure.
