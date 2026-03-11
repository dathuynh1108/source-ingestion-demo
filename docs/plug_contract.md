# Run Steps

Use the full compose file:

```bash
docker compose -f docker-compose.yml up -d --build
```

Enable live generator:

```bash
docker compose -f docker-compose.yml --profile live-gen up -d --build
```

Check:

```bash
docker compose -f docker-compose.yml ps
```

Stop:

```bash
docker compose -f docker-compose.yml down
```
