defmodule OracleSageWeb.SearchChannel do
  use OracleSageWeb, :channel

  def join("search:" <> user_id, _payload, socket) do
    {:ok, assign(socket, :user_id, user_id)}
  end

  def handle_in("search_progress", %{"message" => message, "step" => step}, socket) do
    broadcast(socket, "search_update", %{
      message: message,
      step: step,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
    {:noreply, socket}
  end
end