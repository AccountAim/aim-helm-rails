module AimHelmRailsSpec
  module Identities
    def test_organization
      @test_organization ||= Organization.create!(name: "Test organization")
    end

    def execution_context(actor)
      AimHelmRails::ExecutionContext.new(actor:, tenant: actor.organization)
    end
  end
end

RSpec.configure { it.include AimHelmRailsSpec::Identities }
