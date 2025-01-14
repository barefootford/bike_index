require "rails_helper"

RSpec.describe Notification, type: :model do
  describe "notifiable_display_name" do
    let(:notification) { FactoryBot.create(:notification) }
    it "is blank" do
      expect(notification.notifiable_display_name).to be_blank
    end
    context "donation" do
      let(:payment) { FactoryBot.create(:payment) }
      let(:notification) { FactoryBot.create(:notification, kind: "donation_stolen", notifiable: payment, user: payment.user) }
      it "is payment" do
        expect(notification.notifiable_display_name).to eq "Payment ##{payment.id}"
        expect(notification.sender_display_name).to eq "auto"
      end
    end
  end

  describe "notifications_sent_or_received_by" do
    let(:user) { FactoryBot.create(:user) }
    let(:stolen_notification) { FactoryBot.create(:stolen_notification, sender: user) }
    let!(:notification1) { FactoryBot.create(:notification, user: user) }
    it "gets from and by" do
      expect {
        EmailStolenNotificationWorker.new.perform(stolen_notification.id)
        EmailStolenNotificationWorker.new.perform(stolen_notification.id, true)
      }.to change(Notification, :count).by 2

      expect(Notification.pluck(:kind)).to match_array(%w[confirmation_email stolen_notification_sent stolen_notification_blocked])

      expect(Notification.notifications_sent_or_received_by(user).pluck(:id).uniq.count).to eq 3
      expect(Notification.notifications_sent_or_received_by(user.id).pluck(:id).uniq.count).to eq 3
    end
  end

  describe "calculated_email" do
    let(:notification) { FactoryBot.create(:notification, user: user) }
    let(:user) { FactoryBot.create(:user, email: "stuff@party.eu") }
    it "returns email if user deleted" do
      expect(notification.calculated_email).to eq "stuff@party.eu"
      user.destroy
      notification.reload
      expect(notification.calculated_email).to be_blank
    end
  end

  describe "kind sanity checks" do
    it "doesn't have duplicates" do
      expect(Notification::KIND_ENUM.values.count).to eq Notification::KIND_ENUM.values.uniq.count
      expect(Notification::KIND_ENUM.keys.count).to eq Notification::KIND_ENUM.keys.uniq.count
    end
  end

  describe "sender" do
    let(:notification) { Notification.new(notifiable: notifiable, kind: kind) }
    context "donation" do
      let(:notifiable) { Payment.new }
      let(:kind) { "donation_stolen" }
      it "is auto" do
        expect(notification.sender).to be_blank
      end
    end
    context "customer_contact" do
      let(:user) { User.new(id: 12) }
      let(:notifiable) { CustomerContact.new(creator: user) }
      let(:kind) { "stolen_contact" }
      it "is auto" do
        expect(notification.sender).to eq user
      end
    end
    context "stolen_notification" do
      let(:user) { User.new(id: 12) }
      let(:notifiable) { StolenNotification.new(sender: user) }
      let(:kind) { "stolen_notification_sent" }
      it "is auto" do
        expect(notification.sender).to eq user
      end
    end
    context "user_alert" do
      let(:notifiable) { UserAlert.new(id: 12) }
      let(:kind) { "stolen_notification_sent" }
      it "is auto" do
        expect(notification.sender).to be_blank
      end
    end
  end
end
