defmodule Dandelion.Audit.Migration do
  @moduledoc """
  The table `Dandelion.Audit` writes to, and the trigger that keeps it append-only,
  called from your own migration:

      defmodule MyApp.Repo.Migrations.AddAudit do
        use Ecto.Migration

        def up, do: Dandelion.Audit.Migration.up()
        def down, do: Dandelion.Audit.Migration.down()
      end
  """
  import Ecto.Migration

  def up do
    create_if_not_exists table(:dandelion_audit) do
      add(:at, :utc_datetime_usec, null: false)
      add(:actor, :text, null: false)
      add(:action, :text, null: false)
      add(:subject, :text, null: false)
      add(:details, :jsonb, null: false, default: fragment("'{}'::jsonb"))
      add(:request_id, :text)
    end

    create_if_not_exists(index(:dandelion_audit, [:actor, :id]))
    create_if_not_exists(index(:dandelion_audit, [:subject, :id]))
    create_if_not_exists(index(:dandelion_audit, [:action, :id]))
    create_if_not_exists(index(:dandelion_audit, [:at]))

    # Entries are never changed or deleted — except by Dandelion.Audit.prune/1, which
    # says so for the length of its own transaction.
    execute("""
    CREATE OR REPLACE FUNCTION dandelion_audit_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND current_setting('dandelion.audit_prune', true) = 'on' THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION 'dandelion_audit is append-only (% refused)', TG_OP;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("DROP TRIGGER IF EXISTS dandelion_audit_append_only ON dandelion_audit")

    execute("""
    CREATE TRIGGER dandelion_audit_append_only BEFORE UPDATE OR DELETE ON dandelion_audit
    FOR EACH ROW EXECUTE FUNCTION dandelion_audit_append_only()
    """)

    execute("DROP TRIGGER IF EXISTS dandelion_audit_no_truncate ON dandelion_audit")

    execute("""
    CREATE TRIGGER dandelion_audit_no_truncate BEFORE TRUNCATE ON dandelion_audit
    FOR EACH STATEMENT EXECUTE FUNCTION dandelion_audit_append_only()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS dandelion_audit_no_truncate ON dandelion_audit")
    execute("DROP TRIGGER IF EXISTS dandelion_audit_append_only ON dandelion_audit")
    execute("DROP FUNCTION IF EXISTS dandelion_audit_append_only()")
    drop_if_exists(table(:dandelion_audit))
  end
end
