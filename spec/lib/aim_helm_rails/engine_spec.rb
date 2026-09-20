RSpec.describe AimHelmRails::Engine do
  it "eager loads with the optional adapters" do
    expect { Zeitwerk::Loader.eager_load_all }.not_to raise_error
  end

  it "injects the Rails telemetry adapter into AimHelm" do
    event = nil
    subscriber = ActiveSupport::Notifications
                 .subscribe("aim_helm.append_anomaly") { |notification| event = notification }

    AimHelm.config.telemetry.call(:append_anomaly, session_id: "session-1", count: 1)

    expect(event.payload).to eq(session_id: "session-1", count: 1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
