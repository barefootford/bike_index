require "rails_helper"

RSpec.describe "Bikes API V3", type: :request do
  let(:manufacturer) { FactoryBot.create(:manufacturer) }
  let(:color) { FactoryBot.create(:color) }
  include_context :existing_doorkeeper_app

  describe "find by id" do
    it "returns one with from an id" do
      bike = FactoryBot.create(:bike)
      get "/api/v3/bikes/#{bike.id}", params: {format: :json}
      expect(response.code).to eq("200")
      expect(json_result["bike"]["id"]).to eq(bike.id)
      expect(response.headers["Content-Type"].match("json")).to be_present
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(response.headers["Access-Control-Request-Method"]).to eq("*")
    end

    it "responds with missing" do
      get "/api/v3/bikes/10", params: {format: :json}
      expect(response.code).to eq("404")
      expect(json_result["error"].present?).to be_truthy
      expect(response.headers["Content-Type"].match("json")).to be_present
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(response.headers["Access-Control-Request-Method"]).to eq("*")
    end
  end

  describe "check_if_registered" do
    let(:bike_attrs) do
      {
        organization_slug: organization.id,
        serial: "69 non-example",
        manufacturer: manufacturer.name,
        rear_tire_narrow: "true",
        rear_wheel_bsd: "559",
        color: color.name,
        year: "1969",
        owner_email: phone,
        frame_material: "steel",
        owner_email_is_phone_number: true
      }
    end
    let(:phone) { "2221114444" }
    let(:organization) { FactoryBot.create(:organization) }
    let(:bike) { FactoryBot.create(:bike, :phone_registration, owner_email: phone, serial_number: bike_attrs[:serial]) }
    let!(:ownership) { FactoryBot.create(:ownership, owner_email: phone, is_phone: true, bike: bike) }
    let!(:token) { create_doorkeeper_token(scopes: "read_bikes write_bikes read_organization_membership") }
    it "returns 401" do
      post "/api/v3/bikes/check_if_registered?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
      expect(response.code).to eq("401")
    end
    context "user is organization member" do
      let(:user) { FactoryBot.create(:organization_member) }
      let!(:organization) { user.organizations.first }
      it "returns success" do
        post "/api/v3/bikes/check_if_registered?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
        expect(response.code).to eq("201")
        expect(json_result[:registered].to_s).to eq "true"
        post "/api/v3/bikes/check_if_registered?access_token=#{token.token}", params: bike_attrs.merge(serial: "ffff").to_json, headers: json_headers
        expect(response.code).to eq("201")
        expect(json_result[:registered].to_s).to eq "false"
      end
    end
  end

  describe "create" do
    let(:bike_attrs) do
      {
        serial: "69 non-example",
        manufacturer: manufacturer.name,
        rear_tire_narrow: "true",
        rear_wheel_bsd: "559",
        color: color.name,
        year: "1969",
        owner_email: "fun_times@examples.com",
        frame_material: "steel"
      }
    end
    let!(:token) { create_doorkeeper_token(scopes: "read_bikes write_bikes") }
    before :each do
      FactoryBot.create(:wheel_size, iso_bsd: 559)
    end

    context "no token" do
      let(:token) { nil }
      it "responds with 401" do
        post "/api/v3/bikes", params: bike_attrs.to_json
        expect(response.code).to eq("401")
      end
    end

    context "without write_bikes scope" do
      let!(:token) { create_doorkeeper_token(scopes: "read_bikes") }
      it "fails" do
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
        expect(response.code).to eq("403")
      end
    end

    context "unconfirmed user" do
      let(:user) { FactoryBot.create(:user) }
      let!(:token) { create_doorkeeper_token(scopes: "read_bikes write_bikes unconfirmed") }
      it "fails" do
        expect(user.unconfirmed?).to be_truthy
        expect(token.resource_owner_id).to eq user.id
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
        expect(response.code).to eq("403")
      end
    end

    context "with a phone instead of an email" do
      let(:phone) { "1112224444" }
      let(:phone_bike) { bike_attrs.merge(owner_email: phone, owner_email_is_phone_number: true) }
      it "creates" do
        expect {
          post "/api/v3/bikes?access_token=#{token.token}", params: phone_bike.to_json, headers: json_headers
        }.to change(Bike, :count).by 1
        expect(json_result[:claim_url]).to match(/t=/)

        bike_result = json_result["bike"]
        bike = Bike.last
        expect(bike_result[:id]).to eq bike.id
        expect(bike.phone_registration?).to be_truthy
        expect(bike.owner_email).to eq phone
        expect(bike.phone).to eq phone
        expect(bike.current_ownership.phone_registration?).to be_truthy
        expect(bike.current_ownership.calculated_send_email).to be_falsey
      end
      context "matching phone bike already registered" do
        let(:bike) { FactoryBot.create(:bike, :phone_registration, owner_email: phone, serial_number: phone_bike[:serial]) }
        let!(:ownership) { FactoryBot.create(:ownership, owner_email: phone, is_phone: true, creator: user, bike: bike) }
        it "returns that bike" do
          bike.reload
          expect(user.authorized?(bike)).to be_truthy
          expect(bike.phone_registration?).to be_truthy
          expect(bike.current_ownership.phone_registration?).to be_truthy
          expect {
            post "/api/v3/bikes?access_token=#{token.token}", params: phone_bike.to_json, headers: json_headers
          }.to_not change(Bike, :count)
          expect(json_result[:claim_url]).to be_present
          expect(json_result[:claim_url]).to_not match(/t=/)

          bike_result = json_result["bike"]
          expect(bike_result["id"]).to eq bike.id
          expect(bike_result.to_s).to_not match(phone)
          expect(bike_result.to_s).to_not match(bike.owner_email)
        end
      end
      context "matching bike for user with phone" do
        let!(:bike) { FactoryBot.create(:bike, :with_ownership_claimed, user: user, serial_number: phone_bike[:serial]) }
        it "returns that bike" do
          user.update(phone: phone)
          user.reload
          bike.reload
          expect(user.authorized?(bike)).to be_truthy
          expect(bike.phone_registration?).to be_falsey
          expect(bike.current_ownership.phone_registration?).to be_falsey
          expect {
            post "/api/v3/bikes?access_token=#{token.token}", params: phone_bike.to_json, headers: json_headers
          }.to_not change(Bike, :count)

          bike_result = json_result["bike"]
          expect(bike_result["id"]).to eq bike.id
          expect(bike_result.to_s).to_not match(phone)
          expect(bike_result.to_s).to_not match(bike.owner_email)
        end
      end
    end

    context "given a matching pre-existing bike record" do
      context "if the POSTer is authorized to update" do
        it "does not create a new record" do
          user_email = FactoryBot.create(:user_email, user: user, email: "something@stuff.com", confirmation_token: "fake")
          user_email.reload
          expect(user_email.confirmed?).to be_falsey
          post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

          expect(response.status).to eq(201)
          expect(response.status_message).to eq("Created")
          bike1_result = json_result["bike"]

          post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.merge(owner_email: "something@stuff.com").to_json, headers: json_headers
          bike2_result = json_result["bike"]
          expect(response.status).to eq(302)
          expect(response.status_message).to eq("Found")
          expect(bike1_result["id"]).to eq(bike2_result["id"])
          bike = Bike.find bike1_result["id"]
          expect(bike.owner_email).to eq bike_attrs[:owner_email]
        end

        it "updates the pre-existing record" do
          old_color = FactoryBot.create(:color, name: "old_color")
          new_color = FactoryBot.create(:color, name: "new_color")
          old_manufacturer = FactoryBot.create(:manufacturer, name: "old_manufacturer")
          new_manufacturer = FactoryBot.create(:manufacturer, name: "new_manufacturer")
          old_wheel_size = FactoryBot.create(:wheel_size, name: "old_wheel_size", iso_bsd: 10)
          new_rear_wheel_size = FactoryBot.create(:wheel_size, name: "new_rear_wheel_size", iso_bsd: 11)
          new_front_wheel_size = FactoryBot.create(:wheel_size, name: "new_front_wheel_size", iso_bsd: 12)
          old_cycle_type = CycleType.new("unicycle")
          new_cycle_type = CycleType.new("tricycle")
          old_year = 1969
          new_year = 2001
          bike1 = FactoryBot.create(
            :bike,
            creator: user,
            owner_email: user.email,
            year: old_year,
            manufacturer: old_manufacturer,
            primary_frame_color: old_color,
            cycle_type: old_cycle_type.id,
            rear_wheel_size: old_wheel_size,
            front_wheel_size: old_wheel_size,
            rear_tire_narrow: false,
            frame_material: "aluminum"
          )
          FactoryBot.create(:ownership, bike: bike1, creator: user, owner_email: user.email)

          bike_attrs = {
            serial: bike1.serial_number,
            manufacturer: new_manufacturer.name,
            rear_tire_narrow: true,
            front_wheel_bsd: new_front_wheel_size.iso_bsd,
            rear_wheel_bsd: new_rear_wheel_size.iso_bsd,
            color: new_color.name,
            year: new_year,
            owner_email: user.email,
            frame_material: "steel",
            cycle_type_name: new_cycle_type.slug.to_s
          }
          post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
          bike2 = json_result["bike"]
          expect(bike2["id"]).to eq(bike1.id)
          expect(bike2["serial"]).to eq(bike1.serial_display)
          expect(bike2["year"]).to eq(new_year)
          expect(bike2["frame_colors"].first).to eq(new_color.name)
          expect(bike2["type_of_cycle"]).to eq(new_cycle_type.name)
          expect(bike2["manufacturer_id"]).to eq(old_manufacturer.id)
          expect(bike2["front_wheel_size_iso_bsd"]).to eq(new_front_wheel_size.iso_bsd)
          expect(bike2["rear_wheel_size_iso_bsd"]).to eq(new_rear_wheel_size.iso_bsd)
          expect(bike2["rear_tire_narrow"]).to eq(true)
          expect(bike2["frame_material_slug"]).to eq("steel")
        end
      end

      context "if the matching bike is unclaimed" do
        it "updates if the submitting org is the creation org" do
          bike = FactoryBot.create(:bike_organized)
          FactoryBot.create(:ownership, creator: bike.creator, bike: bike)
          FactoryBot.create(:membership_claimed, user: user, organization: bike.creation_organization)

          bike_attrs = {
            serial: bike.serial_display,
            manufacturer: bike.manufacturer.name,
            color: color.name,
            year: bike.year,
            owner_email: bike.owner_email
          }
          post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

          returned_bike = json_result["bike"]
          expect(response.status).to eq(302)
          expect(response.status_message).to eq("Found")
          expect(returned_bike["id"]).to eq(bike.id)
        end

        it "creates a new record if the submitting org isn't the creation org" do
          bike = FactoryBot.create(:bike_organized)
          FactoryBot.create(:ownership, creator: bike.creator, bike: bike)
          FactoryBot.create(:membership_claimed, user: user)

          bike_attrs = {
            serial: bike.serial_display,
            manufacturer: bike.manufacturer.name,
            color: color.name,
            year: bike.year,
            owner_email: bike.owner_email
          }
          post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

          returned_bike = json_result["bike"]
          expect(response.status).to eq(201)
          expect(response.status_message).to eq("Created")
          expect(returned_bike["id"]).to_not eq(bike.id)
        end
      end

      context "if the matching bike is claimed" do
        let(:can_edit_claimed) { true }
        let(:bike) { FactoryBot.create(:bike_organized, can_edit_claimed: can_edit_claimed) }
        let!(:ownership) { FactoryBot.create(:ownership_claimed, creator: bike.creator, bike: bike) }
        let!(:membership) { FactoryBot.create(:membership_claimed, user: user, organization: bike.creation_organization) }
        let(:bike_attrs) do
          {
            serial: bike.serial_display,
            manufacturer: bike.manufacturer.name,
            color: color.name,
            year: "2012",
            owner_email: bike.owner_email
          }
        end
        it "updates" do
          expect(bike.year).to_not eq 2012
          expect {
            post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
          }.to_not change(Bike, :count)

          returned_bike = json_result["bike"]
          expect(response.status).to eq(302)
          expect(response.status_message).to eq "Found"
          expect(returned_bike["id"]).to eq bike.id
          expect(returned_bike["year"]).to eq 2012
          bike.reload
          expect(bike.year).to eq 2012
        end
        context "can_edit_claimed false" do
          let(:can_edit_claimed) { false }
          it "creates a new bike" do
            expect(bike.year).to_not eq 2012
            expect {
              post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
            }.to change(Bike, :count).by 1

            returned_bike = json_result["bike"]
            expect(response.status).to eq(201)
            expect(response.status_message).to eq "Created"
            expect(returned_bike["id"]).to_not eq bike.id
            bike.reload
            expect(bike.year).to_not eq 2012
          end
        end
      end
    end

    context "given a bike with a pre-existing match by a normalized serial number" do
      it "responds with the match instead of creating a duplicate" do
        bike_attrs = {
          serial: "serial-Ol",
          manufacturer: manufacturer.name,
          color: color.name,
          year: "1969",
          owner_email: "bike-serial-01@examples.com"
        }
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        expect(response.status).to eq(201)
        expect(response.status_message).to eq("Created")
        bike1 = json_result["bike"]

        bike_attrs = bike_attrs.merge(serial: "serial-01")
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        bike2 = json_result["bike"]
        expect(response.status).to eq(302)
        expect(response.status_message).to eq("Found")
        expect(bike1["id"]).to eq(bike2["id"])
      end
    end

    context "given a bike with a pre-existing match by a normalized email" do
      it "responds with the match instead of creating a duplicate" do
        bike_attrs = {
          serial: "serial-01",
          manufacturer: manufacturer.name,
          color: color.name,
          year: "1969",
          owner_email: "bike-serial-01@example.com"
        }
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        expect(response.status).to eq(201)
        expect(response.status_message).to eq("Created")
        bike1 = json_result["bike"]

        bike_attrs = bike_attrs.merge(owner_email: "  bike-serial-01@example.com  ")
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        bike2 = json_result["bike"]
        expect(response.status).to eq(302)
        expect(response.status_message).to eq("Found")
        expect(bike1["id"]).to eq(bike2["id"])
      end
    end

    context "given a bike with a pre-existing match by an owning user's secondary email" do
      it "responds with the match instead of creating a duplicate" do
        user.user_emails.create(email: "secondary-email@example.com")
        bike = FactoryBot.create(:ownership, creator: user).bike

        bike_attrs = {
          serial: bike.serial_display,
          manufacturer: bike.manufacturer.name,
          color: color.name,
          year: bike.year,
          owner_email: user.secondary_emails.first
        }
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        returned_bike = json_result["bike"]
        expect(response.status).to eq(302)
        expect(response.status_message).to eq("Found")
        expect(returned_bike["id"]).to eq(bike.id)
      end
    end

    context "given a bike with a pre-existing match by serial" do
      it "creates a new bike if the match has a different owner" do
        bike = FactoryBot.create(:ownership, creator: user).bike

        bike_attrs = {
          serial: bike.serial_display,
          manufacturer: bike.manufacturer.name,
          color: color.name,
          year: bike.year,
          owner_email: "some-other-owner@example.com"
        }
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers

        returned_bike = json_result["bike"]
        expect(response.status).to eq(201)
        expect(response.status_message).to eq("Created")
        expect(returned_bike["id"]).to_not eq(bike.id)
      end
    end

    it "creates a non example bike, with components" do
      manufacturer = FactoryBot.create(:manufacturer)
      FactoryBot.create(:ctype, name: "wheel")
      FactoryBot.create(:ctype, name: "Headset")
      front_gear_type = FactoryBot.create(:front_gear_type)
      handlebar_type_slug = "bmx"
      components = [
        {
          manufacturer: manufacturer.name,
          year: "1999",
          component_type: "headset",
          description: "yeah yay!",
          serial_number: "69",
          model: "Richie rich"
        },
        {
          manufacturer: "BLUE TEETH",
          front_or_rear: "Both",
          component_type: "wheel"
        }
      ]
      bike_attrs.merge!(components: components,
        front_gear_type_slug: front_gear_type.slug,
        handlebar_type_slug: handlebar_type_slug,
        is_for_sale: true,
        is_bulk: true,
        is_new: true,
        is_pos: true,
        external_image_urls: ["https://files.bikeindex.org/email_assets/bike_photo_placeholder.png"],
        description: "<svg/onload=alert(document.cookie)>")
      expect {
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
      }.to change(EmailOwnershipInvitationWorker.jobs, :size).by(1)
      expect(response.code).to eq("201")
      result = json_result["bike"]
      expect(result["serial"]).to eq(bike_attrs[:serial])
      expect(result["manufacturer_name"]).to eq(bike_attrs[:manufacturer])
      bike = Bike.find(result["id"])
      expect(bike.example).to be_falsey
      expect(bike.is_for_sale).to be_truthy
      expect(bike.frame_material).to eq(bike_attrs[:frame_material])
      expect(bike.components.count).to eq(3)
      expect(bike.components.pluck(:manufacturer_id).include?(manufacturer.id)).to be_truthy
      expect(bike.components.pluck(:ctype_id).uniq.count).to eq(2)
      expect(bike.front_gear_type).to eq(front_gear_type)
      expect(bike.handlebar_type).to eq(handlebar_type_slug)
      expect(bike.external_image_urls).to eq(["https://files.bikeindex.org/email_assets/bike_photo_placeholder.png"])
      ownership = bike.current_ownership
      expect([ownership.pos?, ownership.is_new, ownership.bulk?]).to eq([true, true, false])
      # expect(ownership.origin).to eq 'api_v3'

      # We return things will alert if they're written directly to the dom - worth noting, since it might be a problem
      expect(result["description"]).to eq "<svg/onload=alert(document.cookie)>"
      expect(bike.description).to eq "<svg/onload=alert(document.cookie)>"
    end

    it "doesn't send an email" do
      ActionMailer::Base.deliveries = []
      post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.merge(no_notify: true).to_json, headers: json_headers
      EmailOwnershipInvitationWorker.drain
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(response.code).to eq("201")
    end

    it "creates an example bike" do
      ActionMailer::Base.deliveries = []
      post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.merge(test: true).to_json, headers: json_headers
      EmailOwnershipInvitationWorker.drain
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(response.code).to eq("201")
      result = json_result["bike"]
      expect(result["serial"]).to eq(bike_attrs[:serial])
      expect(result["manufacturer_name"]).to eq(bike_attrs[:manufacturer])
      bike = Bike.unscoped.find(result["id"])
      # expect(bike.current_ownership.origin).to eq 'api_v3'
      expect(bike.example).to be_truthy
      expect(bike.is_for_sale).to be_falsey
    end

    it "creates a stolen bike through an organization and uses the passed phone" do
      organization = FactoryBot.create(:organization)
      user.update_attribute :phone, "0987654321"
      FactoryBot.create(:membership, user: user, organization: organization)
      FactoryBot.create(:country, iso: "US")
      FactoryBot.create(:state, abbreviation: "NY")
      organization.save
      bike_attrs[:organization_slug] = organization.slug
      date_stolen = 1357192800
      bike_attrs[:stolen_record] = {
        phone: "1234567890",
        date_stolen: date_stolen,
        theft_description: "This bike was stolen and that's no fair.",
        country: "US",
        city: "New York",
        street: "278 Broadway",
        zipcode: "10007",
        show_address: true,
        state: "NY",
        police_report_number: "99999999",
        police_report_department: "New York"
      }
      expect {
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
      }.to change(EmailOwnershipInvitationWorker.jobs, :size).by(1)
      expect(json_result).to include("bike")
      expect(json_result["bike"]["serial"]).to eq(bike_attrs[:serial])
      expect(json_result["bike"]["manufacturer_name"]).to eq(bike_attrs[:manufacturer])
      expect(json_result["bike"]["stolen_record"]["date_stolen"]).to eq(date_stolen)
      bike = Bike.find(json_result["bike"]["id"])
      expect(bike.creation_organization).to eq(organization)
      expect(bike.bike_organizations.count).to eq 1
      bike_organization = bike.bike_organizations.first
      expect(bike_organization.organization_id).to eq organization.id
      expect(bike_organization.can_edit_claimed).to be_truthy
      expect(bike.current_ownership.origin).to eq "api_v2" # Because it just inherits v2 :/
      expect(bike.current_ownership.organization).to eq organization
      expect(bike.current_stolen_record_id).to be_present
      expect(bike.current_stolen_record.police_report_number).to eq(bike_attrs[:stolen_record][:police_report_number])
      expect(bike.current_stolen_record.phone).to eq("1234567890")
      expect(bike.current_stolen_record.show_address).to be_falsey
    end

    it "does not register a stolen bike unless attrs are present" do
      bike_attrs[:stolen_record] = {
        phone: "",
        theft_description: "I was away for a little bit and suddenly the bike was gone",
        city: "Chicago"
      }
      expect {
        post "/api/v3/bikes?access_token=#{token.token}", params: bike_attrs.to_json, headers: json_headers
      }.to change(EmailOwnershipInvitationWorker.jobs, :size).by(1)
      expect(json_result).to include("bike")
      expect(json_result["bike"]["serial"]).to eq(bike_attrs[:serial])
      expect(json_result["bike"]["manufacturer_name"]).to eq(bike_attrs[:manufacturer])
      expect(json_result["bike"]["stolen_record"]["date_stolen"]).to be_within(1).of Time.current.to_i
      bike = Bike.find(json_result["bike"]["id"])
      expect(bike.creation_organization).to be_blank
      expect(bike.current_ownership.origin).to eq "api_v2" # Because it just inherits v2 :/
      expect(bike.status_stolen?).to be_truthy
      expect(bike.current_stolen_record_id).to be_present
      expect(bike.current_stolen_record.police_report_number).to be_nil
      expect(bike.current_stolen_record.phone).to be_nil
      expect(bike.current_stolen_record.show_address).to be_falsey
      expect(bike.current_stolen_record.theft_description).to eq "I was away for a little bit and suddenly the bike was gone"
    end
  end

  describe "create v3_accessor" do
    let(:organization) { FactoryBot.create(:organization) }
    let(:bike_attrs) do
      {
        serial: "69 non-example",
        manufacturer: manufacturer.name,
        rear_tire_narrow: "true",
        rear_wheel_bsd: "559",
        color: color.name,
        year: "1969",
        owner_email: "fun_times@examples.com",
        organization_slug: organization.slug,
        cycle_type: "bike"
      }
    end
    let!(:tokenized_url) { "/api/v2/bikes?access_token=#{v2_access_token.token}" }
    before :each do
      FactoryBot.create(:wheel_size, iso_bsd: 559)
    end

    context "with membership" do
      before do
        FactoryBot.create(:membership, user: user, organization: organization, role: "admin")
        organization.save
      end

      context "duplicated serial" do
        context "matching email" do
          it "returns existing bike if authorized by organization" do
            email = bike_attrs[:owner_email]
            bike = FactoryBot.create(:bike, serial_number: bike_attrs[:serial], owner_email: email)
            bike.organizations << organization
            bike.save
            ownership = FactoryBot.create(:ownership, bike: bike, owner_email: email)

            expect(ownership.claimed).to be_falsey
            ActionMailer::Base.deliveries = []
            Sidekiq::Worker.clear_all
            expect {
              post tokenized_url, params: bike_attrs.merge(no_duplicate: true).to_json, headers: json_headers
            }.to change(Bike, :count).by 0

            result = json_result["bike"]
            expect(response.status).to eq(302)
            expect(response.status_message).to eq("Found")
            expect(result["id"]).to eq bike.id

            EmailOwnershipInvitationWorker.drain
            expect(ActionMailer::Base.deliveries).to be_empty
          end
        end

        context "non-matching email" do
          let(:email) { "another_email@example.com" }
          it "creates a bike for organization with v3_accessor, doesn't send email because skip_email" do
            organization.update_attribute :enabled_feature_slugs, ["skip_ownership_email"]
            bike = FactoryBot.create(:bike, serial_number: bike_attrs[:serial], owner_email: email)
            ownership = FactoryBot.create(:ownership, bike: bike, owner_email: email)
            expect(ownership.claimed).to be_falsey
            ActionMailer::Base.deliveries = []
            Sidekiq::Worker.clear_all
            expect {
              post tokenized_url, params: bike_attrs.to_json, headers: json_headers
            }.to change(Bike, :count).by 1
            result = json_result["bike"]

            expect(response.code).to eq("201")
            bike = Bike.find(result["id"])
            expect(bike.creation_organization).to eq(organization)
            expect(bike.creator).to eq(user)
            expect(bike.secondary_frame_color).to be_nil
            expect(bike.rear_wheel_size.iso_bsd).to eq 559
            expect(bike.front_wheel_size.iso_bsd).to eq 559
            expect(bike.rear_tire_narrow).to be_truthy
            expect(bike.front_tire_narrow).to be_truthy
            # expect(bike.current_ownership.origin).to eq 'api_v3'
            expect(bike.current_ownership.organization).to eq organization
            EmailOwnershipInvitationWorker.drain
            expect(ActionMailer::Base.deliveries).to be_empty
          end
        end
      end

      it "doesn't create a bike without an organization with v3_accessor" do
        post tokenized_url, params: bike_attrs.except(:organization_slug).to_json, headers: json_headers
        expect(response.code).to eq("403")
        expect(json_result["error"].is_a?(String)).to be_truthy
        EmailOwnershipInvitationWorker.drain
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "fails to create a bike if the app owner isn't a member of the organization" do
      expect(user.has_membership?).to be_falsey
      post tokenized_url, params: bike_attrs.to_json, headers: json_headers
      expect(response.code).to eq("403")
      expect(json_result["error"].is_a?(String)).to be_truthy
    end
  end

  describe "update" do
    before do
      FactoryBot.create(:color, name: "Orange")
      FactoryBot.create(:country, iso: "US")
    end

    let(:params) do
      {
        year: 1975,
        serial_number: "XXX69XXX",
        description: "updated description",
        primary_frame_color: "orange",
        secondary_frame_color: "black",
        tertiary_frame_color: "orange",
        front_gear_type_slug: "2",
        rear_gear_type_slug: "3",
        handlebar_type_slug: "front"
      }
    end

    let(:url) { "/api/v3/bikes/#{bike.id}?access_token=#{token.token}" }
    let(:ownership) { FactoryBot.create(:ownership, creator_id: user.id) }
    let(:bike) { ownership.bike }
    let!(:token) { create_doorkeeper_token(scopes: "read_user read_bikes write_bikes") }

    it "doesn't update if user doesn't own the bike" do
      other_user = FactoryBot.create(:user)
      bike.current_ownership.update(user_id: other_user.id, claimed: true)
      allow_any_instance_of(Bike).to receive(:type).and_return("unicorn")

      put url, params: params.to_json, headers: json_headers

      expect(response.body.match("do not own that unicorn")).to be_present
      expect(response.code).to eq("403")
    end

    it "doesn't update if not in scope" do
      token.update_attribute :scopes, "public"

      put url, params: params.to_json, headers: json_headers

      expect(response.code).to eq("403")
      expect(response.body).to match(/oauth/i)
      expect(response.body).to match(/permission/i)
    end

    it "updates a bike, adds a stolen record, doesn't update locked attrs" do
      expect(bike.year).to be_nil
      expect(bike.primary_frame_color.name).to eq("Black")

      serial = bike.serial_number
      params[:stolen_record] = {
        city: "Chicago",
        phone: "1234567890",
        show_address: true,
        police_report_number: "999999"
      }
      params[:owner_email] = "foo@new_owner.com"
      params[:primary_frame_color] = "orange"

      expect {
        put url, params: params.to_json, headers: json_headers
      }.to change(Ownership, :count).by(1)

      expect(response.status).to eq(200)
      expect(bike.reload.year).to eq(params[:year])
      expect(bike.primary_frame_color&.name).to eq("Orange")
      expect(bike.serial_number).to eq(serial)
      expect(bike.status_stolen?).to be_truthy
      expect(bike.current_stolen_record.date_stolen.to_i).to be > Time.current.to_i - 10
      expect(bike.current_stolen_record.police_report_number).to eq("999999")
      expect(bike.current_stolen_record.show_address).to be_falsey
    end

    it "updates a bike, adds and removes components" do
      wheels = FactoryBot.create(:ctype, name: "wheel")
      headsets = FactoryBot.create(:ctype, name: "Headset")
      mfg1 = FactoryBot.create(:manufacturer, name: "old manufacturer")
      mfg2 = FactoryBot.create(:manufacturer, name: "new manufacturer")
      comp = FactoryBot.create(:component, manufacturer: mfg1, bike: bike, ctype: headsets)
      comp2 = FactoryBot.create(:component, manufacturer: mfg1, bike: bike, ctype: wheels, serial_number: "old-serial")
      FactoryBot.create(:component)
      bike.reload
      expect(bike.components.count).to eq(2)

      components = [
        {
          manufacturer: mfg2.name,
          year: "1999",
          component_type: "headset",
          description: "C-2",
          model: "Sram GXP Eagle"
        },
        {
          manufacturer: "BLUE TEETH",
          front_or_rear: "Rear",
          description: "C-3"
        },
        {
          id: comp.id,
          destroy: true
        },
        {
          id: comp2.id,
          manufacturer: mfg2.id,
          year: "1999",
          serial: "updated-serial",
          description: "C-1"
        }
      ]
      params[:is_for_sale] = true
      params[:components] = components

      expect {
        put url, params: params.to_json, headers: json_headers
      }.to change(Ownership, :count).by(0)

      expect(response.status).to eq(200)

      bike.reload
      expect(bike.is_for_sale).to be_truthy
      expect(bike.year).to eq(params[:year])

      components = bike.components.reload
      expect(components.count).to eq(3)
      expect(comp2.reload.year).to eq(1999)
      expect(components.map(&:component_model).compact).to eq(["Sram GXP Eagle"])

      manufacturers = components.map { |c| [c.description, c.manufacturer&.name] }.compact
      expect(manufacturers).to(match_array([["C-1", "new manufacturer"],
        ["C-2", "new manufacturer"],
        ["C-3", "Other"]]))

      serials = components.map { |c| [c.description, c.serial_number] }.compact
      expect(serials).to(match_array([["C-1", "updated-serial"],
        ["C-2", nil],
        ["C-3", nil]]))
    end

    it "doesn't remove components that aren't the bikes" do
      FactoryBot.create(:manufacturer)
      comp = FactoryBot.create(:component, bike: bike)
      not_urs = FactoryBot.create(:component)
      components = [
        {
          id: comp.id,
          year: 1999
        }, {
          id: not_urs.id,
          destroy: true
        }
      ]
      params[:components] = components

      put url, params: params.to_json, headers: json_headers

      expect(response.code).to eq("401")
      expect(response.headers["Content-Type"].match("json")).to be_present
      # response.headers['Access-Control-Allow-Origin'].should eq('*')
      # response.headers['Access-Control-Request-Method'].should eq('*')
      expect(bike.reload.components.reload.count).to eq(1)
      expect(bike.components.pluck(:year).first).to eq(1999) # Feature, not a bug?
      expect(not_urs.reload.id).to be_present
    end

    context "unclaimed bike" do
      let(:ownership) { FactoryBot.create(:ownership, owner_email: user.email, claimed: false) }
      it "claims a bike and updates if it should" do
        bike.reload
        expect(bike.year).to be_nil
        expect(bike.owner).not_to eq user
        expect(bike.creator).not_to eq user
        put url, params: params.to_json, headers: json_headers
        expect(response.code).to eq("200")
        expect(response.headers["Content-Type"].match("json")).to be_present
        expect(bike.reload.current_ownership.claimed).to be_truthy
        expect(bike.owner).to eq(user)
        expect(bike.year).to eq(params[:year])
      end
    end

    context "organization bike" do
      let(:organization) { FactoryBot.create(:organization) }
      let(:og_creator) { FactoryBot.create(:organization_member, organization: organization) }
      let(:bike) { FactoryBot.create(:bike_organized, creation_organization: organization, creator: og_creator) }
      let(:ownership) { bike.ownerships.first }
      let(:user) { FactoryBot.create(:organization_member, organization: organization) }
      let(:params) { {year: 1999, external_image_urls: ["https://files.bikeindex.org/email_assets/logo.png"]} }
      let!(:token) { create_doorkeeper_token(scopes: "read_user read_bikes write_bikes") }
      it "permits updating" do
        bike.reload
        expect(bike.public_images.count).to eq 0
        expect(bike.owner).to_not eq(user)
        expect(bike.authorized_by_organization?(u: user)).to be_truthy
        expect(bike.authorized?(user)).to be_truthy
        expect(bike.claimed?).to be_falsey
        expect(bike.current_ownership.claimed?).to be_falsey
        put url, params: params.to_json, headers: json_headers
        expect(response.code).to eq("200")
        expect(response.headers["Content-Type"].match("json")).to be_present
        bike.reload
        expect(bike.claimed?).to be_falsey
        expect(bike.authorized_by_organization?(u: user)).to be_truthy
        expect(bike.reload.owner).to_not eq user
        expect(bike.year).to eq params[:year]
        expect(bike.external_image_urls).to eq([]) # Because we haven't created another bparam - this could change though
        expect(bike.public_images.count).to eq 1
      end
      context "updating email address to a new owner without an existing account" do
        before do
          bike.reload # Ensure it's established
          ActionMailer::Base.deliveries = []
          Sidekiq::Worker.clear_all
          Sidekiq::Testing.inline!
        end
        after { Sidekiq::Testing.fake! }
        let(:new_email) { "newuser@example.com" }
        let(:bike_organization) { bike.bike_organizations.first }
        it "creates a new ownership, emails owner, permits organization editing until has been claimed" do
          expect(og_creator.reload.authorized?(organization)).to be_truthy
          expect(user.reload.authorized?(organization)).to be_truthy
          expect(og_creator.id).to_not eq user.id
          bike.reload
          expect(bike.bike_organizations.count).to eq 1
          expect(bike.public_images.count).to eq 0
          expect(bike.user).to be_blank
          expect(bike.owner).to_not eq(user)
          expect(bike.authorized_by_organization?(u: user)).to be_truthy
          expect(bike.authorized?(user)).to be_truthy
          expect(bike.authorized?(og_creator))
          expect(bike.claimed?).to be_falsey
          expect(bike.current_ownership.claimed?).to be_falsey
          expect(bike_organization.can_edit_claimed).to be_truthy
          expect {
            put url, params: {owner_email: "newuser@EXAMPLE.com "}.to_json, headers: json_headers
          }.to change(Ownership, :count).by(1)
          expect(response.code).to eq("200")
          expect(response.headers["Content-Type"].match("json")).to be_present
          bike.reload
          ownership.reload
          expect(ownership.current?).to be_falsey
          expect(bike_organization.reload.can_edit_claimed).to be_truthy # Because the ownership hasn't been claimed yet
          expect(bike.owner_email).to eq new_email
          expect(bike.user).to be_blank
          expect(bike.claimed?).to be_falsey
          expect(bike.current_ownership.id).to_not eq ownership.id
          expect(bike.authorized?(user)).to be_truthy
          expect(bike.authorized?(og_creator)).to be_truthy
          expect(bike.authorized_by_organization?(u: og_creator)).to be_truthy
          current_ownership = bike.current_ownership
          expect(current_ownership.creator_id).to eq user.id
          expect(current_ownership.owner_email).to eq new_email
          expect(current_ownership.organization_id).to eq organization.id
          expect(ActionMailer::Base.deliveries.count).to eq 1
          mail = ActionMailer::Base.deliveries.last
          expect(mail.subject).to eq("Confirm your #{organization.name} Bike Index registration")
          expect(mail.reply_to).to eq(["contact@bikeindex.org"])
          expect(mail.from).to eq(["contact@bikeindex.org"])
          expect(mail.to).to eq([new_email])
        end
      end
    end

    context "updating email address to a new owner with an existing account" do
      let!(:new_user) { FactoryBot.create(:user_confirmed, email: "newuser@example.com") }
      let(:ownership) { FactoryBot.create(:ownership, owner_email: user.email, user: user, claimed: false) }
      before do
        bike.reload # Ensure it's established
        ActionMailer::Base.deliveries = []
        Sidekiq::Worker.clear_all
        Sidekiq::Testing.inline!
      end
      after { Sidekiq::Testing.fake! }
      it "creates a new ownership, emails owner" do
        expect(bike.owner_email).to eq user.email
        expect(bike.claimed?).to be_falsey
        expect(bike.user).to eq user
        expect(bike.authorized?(user)).to be_truthy
        expect(bike.owner).not_to eq user
        expect {
          put url, params: {owner_email: "newuser@EXAMPLE.com "}.to_json, headers: json_headers
        }.to change(Ownership, :count).by(1)
        expect(response.code).to eq("200")
        expect(response.headers["Content-Type"].match("json")).to be_present
        bike.reload
        ownership.reload
        expect(ownership.claimed?).to be_truthy
        expect(ownership.current?).to be_falsey
        expect(bike.owner_email).to eq new_user.email
        expect(bike.user).to eq new_user
        expect(bike.claimed?).to be_falsey
        expect(bike.current_ownership.id).to_not eq ownership.id
        current_ownership = bike.current_ownership
        expect(current_ownership.creator_id).to eq user.id
        expect(current_ownership.owner_email).to eq new_user.email
        expect(ActionMailer::Base.deliveries.count).to eq 1
        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to eq("Confirm your Bike Index registration")
        expect(mail.reply_to).to eq(["contact@bikeindex.org"])
        expect(mail.from).to eq(["contact@bikeindex.org"])
        expect(mail.to).to eq([new_user.email])
      end
    end
  end

  describe "post id/image" do
    let!(:token) { create_doorkeeper_token(scopes: "read_user write_bikes") }
    it "doesn't post an image to a bike if the bike isn't owned by the user" do
      bike = FactoryBot.create(:ownership).bike
      file = File.open(File.join(Rails.root, "spec", "fixtures", "bike.jpg"))
      url = "/api/v3/bikes/#{bike.id}/image?access_token=#{token.token}"
      expect(bike.public_images.count).to eq(0)
      post url, params: {file: Rack::Test::UploadedFile.new(file)}
      expect(response.code).to eq("403")
      expect(response.headers["Content-Type"].match("json")).to be_present
      expect(bike.reload.public_images.count).to eq(0)
    end

    it "errors on non permitted file extensions" do
      bike = FactoryBot.create(:ownership, creator_id: user.id).bike
      file = File.open(File.join(Rails.root, "spec", "spec_helper.rb"))
      url = "/api/v3/bikes/#{bike.id}/image?access_token=#{token.token}"
      expect(bike.public_images.count).to eq(0)
      post url, params: {file: Rack::Test::UploadedFile.new(file)}
      expect(response.body.match(/not allowed to upload .?.rb/i)).to be_present
      expect(response.code).to eq("401")
      expect(bike.reload.public_images.count).to eq(0)
    end

    it "posts an image" do
      bike = FactoryBot.create(:ownership, creator_id: user.id).bike
      file = File.open(File.join(Rails.root, "spec", "fixtures", "bike.jpg"))
      url = "/api/v3/bikes/#{bike.id}/image?access_token=#{token.token}"
      expect(bike.public_images.count).to eq(0)
      post url, params: {file: Rack::Test::UploadedFile.new(file)}
      expect(response.code).to eq("201")
      expect(response.headers["Content-Type"].match("json")).to be_present
      expect(bike.reload.public_images.count).to eq(1)
    end
  end

  describe "delete id/image" do
    let!(:token) { create_doorkeeper_token(scopes: "read_user write_bikes") }
    let(:ownership) { FactoryBot.create(:ownership, creator_id: user.id) }
    let(:bike) { ownership.bike }
    let!(:public_image) { FactoryBot.create(:public_image, imageable: bike) }
    it "deletes an image" do
      bike.reload
      expect(bike.public_images.count).to eq(1)
      delete "/api/v3/bikes/#{bike.id}/images/#{public_image.id}?access_token=#{token.token}"
      expect(response.code).to eq("200")
      expect(json_result["bike"]["public_images"].count).to eq 0
      expect(bike.reload.public_images.count).to eq(0)
    end
    context "not users image" do
      let(:public_image) { FactoryBot.create(:public_image) }
      it "doesn't delete an image to a bike if the bike isn't owned by the user" do
        bike.reload
        delete "/api/v3/bikes/#{bike.id}/images/#{public_image.id}?access_token=#{token.token}"
        expect(response.code).to eq("404")
        public_image.reload
        expect(public_image).to be_present
      end
    end
  end

  describe "send_stolen_notification" do
    let(:bike) { FactoryBot.create(:stolen_bike, :with_ownership, creator: user) }
    let(:params) { {message: "Something I'm sending you"} }
    let(:url) { "/api/v3/bikes/#{bike.id}/send_stolen_notification?access_token=#{token.token}" }
    let!(:token) { create_doorkeeper_token(scopes: "read_user") }

    it "fails to send a stolen notification without read_user" do
      token.update_attribute :scopes, "public"
      post url, params: params.to_json, headers: json_headers
      expect(response.code).to eq("403")
      expect(response.body).to match("OAuth")
      expect(response.body).to match(/permission/i)
      expect(response.body).to_not match("is not stolen")
    end

    it "fails if the bike isn't stolen" do
      bike.current_stolen_record.add_recovery_information
      expect(bike.reload.status).to eq "status_with_owner"
      post url, params: params.to_json, headers: json_headers
      expect(response.code).to eq("400")
      expect(response.body.match("is not stolen")).to be_present
    end

    it "fails if the bike isn't owned by the access token user" do
      bike.current_ownership.update(user_id: FactoryBot.create(:user).id, claimed: true)
      post url, params: params.to_json, headers: json_headers
      expect(response.code).to eq("403")
      expect(response.body.match("application is not approved")).to be_present
    end

    it "sends a notification" do
      expect(bike.reload.status).to eq "status_stolen"
      expect {
        post url, params: params.to_json, headers: json_headers
      }.to change(EmailStolenNotificationWorker.jobs, :size).by(1)
      expect(response.code).to eq("201")
    end
  end
end
