defmodule OracleSage.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OracleSageWeb.Telemetry,
      OracleSage.Repo,
      {DNSCluster, query: Application.get_env(:oracle_sage, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: OracleSage.PubSub},
      # Start a worker by calling: OracleSage.Worker.start_link(arg)
      # {OracleSage.Worker, arg},
      # Start to serve requests, typically the last entry
      OracleSageWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OracleSage.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OracleSageWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
