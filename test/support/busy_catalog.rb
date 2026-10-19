# frozen_string_literal: true

# A TRANSIENT busy catalog for the loaders' abort tests: the first statement
# matching +pattern+ fails exactly as SQLite's busy timeout surfaces through
# Sequel (a plain Sequel::DatabaseError carrying "database is locked" — no
# constraint subclass), and every statement after it succeeds. That is the
# production shape — another writer outlasts the busy timeout once, then
# lets go — and the one a too-broad per-document rescue would launder into
# a quarantine while the rest of the load carried on.
module BusyCatalog
  BUSY_MESSAGE = "SQLite3::BusyException: database is locked"

  # Prepended to one Database instance's singleton class.
  module FailOnce
    attr_accessor :busy_pattern

    %i[execute execute_dui execute_insert].each do |name|
      define_method(name) do |sql, opts = Sequel::OPTS, &block|
        if busy_pattern && sql.is_a?(String) && sql.match?(busy_pattern)
          self.busy_pattern = nil
          raise Sequel::DatabaseError, BUSY_MESSAGE
        end
        super(sql, opts, &block)
      end
    end
  end

  def busy_once!(db, pattern)
    db.singleton_class.prepend(FailOnce) unless db.singleton_class.include?(FailOnce)
    db.busy_pattern = pattern
  end
end
