# A database that can't be reached or doesn't answer (DBConnection.ConnectionError)
# is "service unavailable", not a bug in the request: 503, not 500. A load balancer
# or a client then knows to retry elsewhere or later. ≈ mapping `sql.ErrConnDone` /
# a context deadline to 503 in a Go error middleware.
defimpl Plug.Exception, for: DBConnection.ConnectionError do
  def status(_exception), do: 503
  def actions(_exception), do: []
end
