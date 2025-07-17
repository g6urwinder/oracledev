defmodule OracleSage.Repo do
  use Ecto.Repo,
    otp_app: :oracle_sage,
    adapter: Ecto.Adapters.Postgres
end
