# frozen_string_literal: true

RSpec.describe AimHelm::Events::LeasedSink do
  let(:user) do
    User.create!(organization: test_organization, name: "Sink User",
                 email: "sink-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:session) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:lease) { session.hold_lease(claimed_by: "worker-1") }
  let(:aim_helm_session) { AimHelm.session(session.id) }
  let(:sink) { described_class.new(session: aim_helm_session, lease:, sink: downstream) }
  let(:event) { AimHelm::Event.build(type: :"message.delta", delta: "hello") }
  let(:downstream) { instance_double(AimHelm::Events::Publisher, call: nil, close: nil) }

  it "renews at most once per local interval while forwarding every event" do
    allow(sink).to receive(:monotonic_time).and_return(0.0, 29.0, 30.0, 30.1)
    allow(lease).to receive(:heartbeat?).and_return(true)
    4.times { sink.call(event) }
    sink.close

    expect(lease).to have_received(:heartbeat?).once
    expect(downstream).to have_received(:call).with(event).exactly(4).times
    expect(downstream).to have_received(:close).once
  end

  it "aborts before broadcasting after lease ownership is lost" do
    allow(sink).to receive(:monotonic_time).and_return(0.0, 30.0)
    allow(lease).to receive(:heartbeat?).and_return(false)
    sink.call(event)

    expect { sink.call(event) }.to raise_error(AimHelm::LeaseLostError, /ownership was lost/)
    expect(downstream).to have_received(:call).once
  end
end
