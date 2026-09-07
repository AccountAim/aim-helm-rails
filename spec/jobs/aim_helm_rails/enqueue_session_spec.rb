RSpec.describe "Enqueuing a session turn", type: :job do
  self.use_transactional_tests = false

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    AimHelmRails::Session.find_by(id: @session_id)&.destroy!
    @actor&.destroy!
    ActiveJob::Base.queue_adapter = original
  end

  before do
    @actor = Organization.create!(name: "Queue actor")
    @session_id = SecureRandom.uuid_v7
    definition = AimHelm.agent("gpt-5.6-luna")
    allow(AimHelmRails.host)
      .to receive(:helmsman).with("probe").and_return(double(agent: definition))
  end

  def enqueued_jobs = AimHelmRails::AdvanceSessionJob.queue_adapter.enqueued_jobs

  def queue_turn
    chat = AimHelmRails::Session.create!(id: @session_id, actor: @actor, tenant: @actor,
                                         helmsman: "probe")
    AimHelmRails::Runtime.run(chat, "Read the report")
  end

  it "enqueues only after the outermost transaction commits its session and entries" do
    AimHelmRails::Session.transaction do
      AimHelmRails::Session.transaction(requires_new: true) do
        queue_turn
        expect(enqueued_jobs).to be_empty
      end

      expect(enqueued_jobs).to be_empty
    end

    expect(enqueued_jobs.sole.fetch(:args).first).to eq(@session_id)
    # A worker uses its own connection, so observe committed data there too.
    kinds = Thread.new do
      AimHelmRails::Session.connection_pool.with_connection do
        AimHelmRails::Session.find(@session_id).entries.pluck(:kind)
      end
    end.value
    expect(kinds).to include("run_record", "user")
  end

  it "does not enqueue when the outer transaction rolls back" do
    AimHelmRails::Session.transaction do
      queue_turn
      raise ActiveRecord::Rollback
    end

    expect(enqueued_jobs).to be_empty
    expect(AimHelmRails::Session.exists?(@session_id)).to be(false)
  end

  it "does not enqueue a turn rolled back to a savepoint" do
    AimHelmRails::Session.transaction do
      AimHelmRails::Session.transaction(requires_new: true) do
        queue_turn
        raise ActiveRecord::Rollback
      end
    end

    expect(enqueued_jobs).to be_empty
    expect(AimHelmRails::Session.exists?(@session_id)).to be(false)
  end
end
