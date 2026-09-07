RSpec.describe AimHelmRails::Attachment, type: :model do
  let(:actor) { Organization.create!(name: "Service actor") }
  let(:tenant) { test_organization }
  let(:chat) { AimHelmRails::Session.create!(actor:, tenant:) }
  let(:attachment) { upload }

  def upload(**attributes)
    path = AimHelmRails::Engine.root.join("spec/fixtures/aim_helm_rails/vision.png")
    file = { io: File.open(path), filename: "vision.png", content_type: "image/png" }
    described_class.create!(actor:, tenant:, file:, **attributes)
  end

  def claim(gids, **attributes)
    described_class.claim!(gids, session: chat, actor:, tenant:, **attributes)
  end

  it "stages a file with generic identities without creating a session" do
    expect { attachment }.not_to change(AimHelmRails::Session, :count)
    expect(attachment.reload).to have_attributes(actor:, tenant:, session: nil)
    expect(attachment.actor_gid).to eq(actor.to_gid.to_s)
  end

  it "claims staged files once and preserves the uploader" do
    expect(claim([attachment.to_gid_param])).to eq([attachment])
    expect(attachment.reload).to have_attributes(session: chat, actor:)

    expect { claim([attachment.to_gid_param]) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "rejects another actor, tenant, expired file, and another model's gid" do
    foreign_actor = Organization.create!(name: "Other actor")
    foreign_tenant = Organization.create!(name: "Other tenant")
    refused = [upload(actor: foreign_actor), upload(tenant: foreign_tenant),
               upload(created_at: 2.days.ago)]

    [*refused.map(&:to_gid_param), actor.to_gid_param, "garbage"].each do |gid|
      expect { claim([gid]) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    expect(refused.map { it.reload.session_id }).to all(be_nil)
  end

  it "rolls back the complete claim when any reference is unavailable" do
    valid = attachment.to_gid_param

    expect { claim([valid, upload(actor: tenant).to_gid_param]) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(attachment.reload.session).to be_nil
  end

  it "does not move a file to another chat" do
    claim([attachment.to_gid_param])
    other_chat = AimHelmRails::Session.create!(actor:, tenant:)

    expect { claim([attachment.to_gid_param], session: other_chat) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(attachment.reload.session).to eq(chat)
  end

  it "resolves only this chat's attachments, including from its subagents" do
    claim([attachment.to_gid_param])
    foreign = upload(session: AimHelmRails::Session.create!(actor:, tenant:))
    child = AimHelmRails::Session.create!(actor:, tenant:, parent_session: chat)

    references = AimHelmRails::Attachments.resolve(
      [attachment.to_gid_param, foreign.to_gid_param], session: child
    )

    expect(references.pluck(:gid)).to eq([attachment.to_gid_param])
  end

  it "purges abandoned staging but preserves recent and claimed uploads" do
    abandoned = upload(created_at: 2.days.ago)
    claimed = upload(session: chat, created_at: 2.days.ago)
    recent = attachment

    AimHelmRails::PurgeStagedAttachmentsJob.perform_now

    expect(described_class.exists?(abandoned.id)).to be(false)
    expect(described_class.where(id: [claimed.id, recent.id]).count).to eq(2)
  end

  it "destroys chat attachments with the session" do
    claim([attachment.to_gid_param])

    expect { chat.destroy! }.to change(described_class, :count).by(-1)
  end
end
