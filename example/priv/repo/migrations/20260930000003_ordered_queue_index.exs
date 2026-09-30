defmodule Platform.Database.Repo.Migrations.OrderedQueueIndex do
  use Ecto.Migration

  def up do
    # Platform.Queue.Ordered asks "is an earlier job of this key unfinished?"
    # on every run; this keeps that cheap.
    create index(:oban_jobs, ["(meta->>'ordered_key')", :id],
             where:
               "state IN ('available', 'scheduled', 'executing', 'retryable') AND meta ? 'ordered_key'",
             name: :oban_jobs_ordered_key_index
           )
  end

  def down do
    drop index(:oban_jobs, [], name: :oban_jobs_ordered_key_index)
  end
end
