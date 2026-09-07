RSpec.describe AimHelmRails::Engine do
  it "names the missing host configuration when bootstrapping an integration" do
    allow(AimHelmRails).to receive(:host).and_call_original
    allow(AimHelmRails).to receive(:host_class).and_return(nil)

    expect { AimHelmRails.host }
      .to raise_error(AimHelm::ConfigurationError, /AimHelmRails.host_class/)
  end

  it "uses session_model as configuration sugar for store" do
    builder = AimHelm::Config::Builder.new(AimHelm.config)

    builder.session_model = AimHelmRails::Session
    expect(builder.store).to be_a(AimHelm::Stores::ActiveRecord)
    expect(builder.store.session_model).to equal(AimHelmRails::Session)

    store = AimHelm::Stores::Memory.new
    builder.store = store
    expect(builder.store).to equal(store)
  end

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
