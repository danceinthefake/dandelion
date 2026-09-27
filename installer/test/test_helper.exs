# Integration tests generate a project and run its own test suite; they need
# network (hex) and the example's Postgres (docker compose up -d in example/).
# Run them with: mix test --include integration
ExUnit.start(exclude: [:integration])
