require "rails_helper"

RSpec.describe TsvCreator do
  describe "create_manufacturer" do
    it "makes mnfgs"
  end

  describe "sent_to_uploader" do
    it "sends to uploader"
  end

  describe "create_organization_count" do
    it "creates tsv with output bikes" do
      bike = FactoryBot.create(:bike_organized)
      organization = bike.creation_organization
      creator = TsvCreator.new
      target = "#{creator.org_counts_header}#{creator.org_count_row(bike)}"
      expect_any_instance_of(TsvUploader).to receive(:store!)
      output = creator.create_org_count(organization)
      expect(File.read(output)).to eq(target)
      expect(FileCacheMaintainer.files.is_a?(Array)).to be_truthy
    end
  end

  describe "create_daily_tsvs" do
    it "calls create_stolen and create_stolen_with_reports with scoped query" do
      stolen_record = FactoryBot.create(:stolen_record, current: true, tsved_at: nil)
      tsv_creator = TsvCreator.new
      expect(tsv_creator).to receive(:create_stolen_with_reports).with(true, stolen_records: StolenRecord.approveds_with_reports.tsv_today)
      expect(tsv_creator).to receive(:create_stolen).with(true, stolen_records: StolenRecord.approveds.tsv_today)

      tsv_creator.create_daily_tsvs
      expect(tsv_creator.file_prefix).to eq("/spec/fixtures/tsv_creation/#{Time.current.year}_#{Time.current.month}_#{Time.current.day}_")
      stolen_record.reload
      expect(stolen_record.tsved_at).to be_present
    end
  end
end
