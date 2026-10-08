# A database that can't be reached or doesn't answer (DBConnection.ConnectionError)
# is "service unavailable", not a bug in the request: 503, not 500. A load balancer
# or a client then knows to retry elsewhere or later. ≈ mapping `sql.ErrConnDone` /
# a context deadline to 503 in a Go error middleware.
defimpl Plug.Exception, for: DBConnection.ConnectionError do
  def status(_exception), do: 503
  def actions(_exception), do: []
end

# A statement the database gave up on (our query timeout cancels it: Postgres says
# 57014): the same story, a retry may work. Any other database error stays a 500.
# This replaces phoenix_ecto's own mapping (config/config.exs excludes it), keeping
# its one case: text the database can't store is the client's 400.
defimpl Plug.Exception, for: Postgrex.Error do
  def status(%{postgres: %{code: :query_canceled}}), do: 503
  def status(%{postgres: %{code: :character_not_in_repertoire}}), do: 400
  def status(_exception), do: 500
  def actions(_exception), do: []
end
