module API
  module V2
    class Bikes < API::Base
      include API::V2::Defaults

      helpers do
        params :bike_attrs do
          optional :rear_wheel_bsd, type: Integer, desc: "Rear wheel iso bsd (has to be one of the `selections`)"
          optional :rear_tire_narrow, type: Boolean, desc: "Boolean. Is it a skinny tire?"
          optional :front_wheel_bsd, type: String, desc: "Copies `rear_wheel_bsd` if not set"
          optional :front_tire_narrow, type: Boolean, desc: "Copies `rear_tire_narrow` if not set"
          optional :frame_model, type: String, desc: "What frame model?"
          optional :year, type: Integer, desc: "What year was the frame made?"
          optional :description, type: String, desc: "General description"
          optional :primary_frame_color, type: String, values: COLOR_NAMES, desc: "Main color of frame (case sensitive match)"
          optional :secondary_frame_color, type: String, values: COLOR_NAMES, desc: "Secondary color (case sensitive match)"
          optional :tertiary_frame_color, type: String, values: COLOR_NAMES, desc: "Third color (case sensitive match)"
          optional :rear_gear_type_slug, type: String, desc: "rear gears (has to be one of the `selections`)"
          optional :front_gear_type_slug, type: String, desc: "front gears (has to be one of the `selections`)"
          optional :handlebar_type_slug, type: String, desc: "handlebar type (has to be one of the `selections`)"
          optional :no_notify, type: Boolean, desc: "On create or ownership change, don't notify the new owner."
          optional :is_for_sale, type: Boolean
          optional :frame_material, type: String, values: Bike.frame_materials.keys, desc: "Frame material type"
          optional :external_image_urls, type: Array, desc: "Image urls to include with registration, if images are already on the internet"

          optional :stolen_record, type: Hash do
            optional :phone, type: String, desc: "Owner's phone number, **required to create stolen**"
            optional :city, type: String, desc: "City where stolen <br> **required to create stolen**"
            optional :country, type: String, values: COUNTRY_ISOS, desc: "Country the bike was stolen"
            optional :zipcode, type: String, desc: "Where the bike was stolen from"
            optional :state, type: String, desc: "State postal abbreviation if in US - e.g. OR, IL, NY"
            optional :address, type: String, desc: "Public. Use an intersection if you'd prefer the specific address not be revealed"
            optional :date_stolen, type: Integer, desc: "When was the bike stolen (defaults to current time)"

            optional :police_report_number, type: String, desc: "Police report number"
            optional :police_report_department, type: String, desc: "Police department reported to (include if report number present)"
            # show_address NO LONGER ACTUALLY DOES ANYTHING. Keeping so that the API doesn't change
            optional :show_address, type: Boolean, desc: "Display the exact address the theft happened at"

            optional :theft_description, type: String, desc: "stuff"

            # link to LOCKING options!
            # optional :locking_description_slug, type: String, desc: "Locking description. description."
            # optional :lock_defeat_description_slug, type: String, desc: "Lock defeat description. One of the values from lock defeat desc"
            # optional :phone_for_everyone, type: Boolean, default: false, desc: 'Show phone number to non logged in users'
            # optional :phone_for_users, type: Boolean, default: true, desc: 'Show phone to logged in users'
          end
        end

        params :components_attrs do
          optional :manufacturer, type: String, desc: "Manufacturer name or ID"
          # [Manufacturer name or ID](api_v2#!/manufacturers/GET_version_manufacturers_format)
          optional :component_type, type: String, desc: "Type of component", values: CTYPE_NAMES
          optional :model, type: String, desc: "Component model"
          optional :year, type: Integer, desc: "Component year"
          optional :description, type: String, desc: "Component description"
          optional :serial, type: String, desc: "Component serial"
          optional :front_or_rear, type: String, desc: "Component front_or_rear"
        end

        def creation_user_id
          if current_user.id == ENV["V2_ACCESSOR_ID"].to_i
            org = params[:organization_slug].present? && Organization.friendly_find(params[:organization_slug])
            if org && current_token.application.owner.present? && current_token.application.owner.admin_of?(org)
              return org.auto_user_id
            end
            error!("Permanent tokens can only be used to create bikes for organizations your are an admin of", 403)
          end
          current_user.id
        end

        def creation_state_params
          {
            is_bulk: params[:is_bulk],
            is_pos: params[:is_pos],
            is_new: params[:is_new]
          }.as_json
        end

        def find_bike
          @bike = Bike.unscoped.find(params[:id])
        end

        # Search for a bike matching the provided serial number / owner email
        def find_owned_bike
          BikeFinder.find_matching(serial: params[:serial],
            owner_email: params[:owner_email_is_phone_number] ? nil : params[:owner_email],
            phone: params[:owner_email_is_phone_number] ? params[:owner_email] : nil)
        end

        def created_bike_serialized(bike, include_claim_token)
          serialized = BikeV2ShowSerializer.new(bike, root: false)
          claim_url = serialized.url + (include_claim_token ? "?t=#{bike.current_ownership.token}" : "")
          {bike: serialized, claim_url: claim_url}
        end

        def authorize_bike_for_user(addendum = "")
          return true if @bike.authorize_and_claim_for_user(current_user)
          error!("You do not own that #{@bike.type}#{addendum}", 403)
        end
      end

      resource :bikes do
        desc "View bike with a given ID"
        params do
          requires :id, type: Integer, desc: "Bike id"
        end
        get ":id" do
          BikeV2ShowSerializer.new(find_bike, root: "bike").as_json
        end

        desc "Check if a bike is already registered", {
          authorizations: {oauth2: [{scope: :write_bikes}]},
          notes: "**Requires** `read_organizations` **in the access token** you use to make the request."
        }
        params do
          requires :serial, type: String, desc: "The serial number for the bike"
          requires :manufacturer, type: String, desc: "Manufacturer name or ID"
          # [Manufacturer name or ID](api_v2#!/manufacturers/GET_version_manufacturers_format)
          requires :owner_email, type: String, desc: "Owner email"
          optional :owner_email_is_phone_number, type: Boolean, desc: "If using a phone number for registration, rather than email"
          requires :color, type: String, desc: "Main color or paint - does not have to be one of the accepted colors"
          requires :organization_slug, type: String, desc: "Organization (ID or slug) bike should be created by. **Only works** if user is a member of the organization"
          optional :cycle_type_name, type: String, values: CYCLE_TYPE_NAMES, default: "bike", desc: "Type of cycle (case sensitive match)"
          use :bike_attrs
        end
        post "check_if_registered" do
          organization = Organization.friendly_find(params[:organization_slug])
          if organization.present? && current_user.authorized?(organization)
            {registered: find_owned_bike.present?}
          else
            error!("You are not authorized for that organization", 401)
          end
        end

        desc "Add a bike to the Index!<span class='accstr'>*</span>", {
          authorizations: {oauth2: [{scope: :write_bikes}]},
          notes: <<-NOTE
            **Requires** `write_bikes` **in the access token** you use to create the bike.

            <hr>

            **Creating test bikes**: To create test bikes, set `test` to true. These bikes:

            - Do not show turn up in searches
            - Do not send an email to the owner on creation
            - Are automatically deleted after a few days
            - Can be viewed in the API /v3/bikes/{id} (same as non-test bikes)
            - Can be viewed on the HTML site /bikes/{id} (same as non-test bikes)

            *`test` is automatically marked true on this documentation page. Set it to false it if you want to create actual bikes*

            **Ownership**: Bikes you create will be created by the user token you authenticate with, but they will be sent to the email address you specify.

          NOTE
        }
        params do
          requires :serial, type: String, desc: "The serial number for the bike"
          requires :manufacturer, type: String, desc: "Manufacturer name or ID"
          # [Manufacturer name or ID](api_v2#!/manufacturers/GET_version_manufacturers_format)
          requires :owner_email, type: String, desc: "Owner email"
          optional :owner_email_is_phone_number, type: Boolean, desc: "If using a phone number for registration, rather than email"
          requires :color, type: String, desc: "Main color or paint - does not have to be one of the accepted colors"
          optional :test, type: Boolean, desc: "Is this a test bike?"
          optional :organization_slug, type: String, desc: "Organization (ID or slug) bike should be created by. **Only works** if user is a member of the organization"
          optional :cycle_type_name, type: String, values: CYCLE_TYPE_NAMES, default: "bike", desc: "Type of cycle (case sensitive match)"
          use :bike_attrs
          optional :components, type: Array do
            use :components_attrs
          end
        end
        post "/" do
          found_bike = find_owned_bike
          # if a matching bike is and can be updated by the submitter, update
          # existing record instead of creating a new one
          if found_bike.present? && found_bike.authorized?(current_user)
            # prepare params
            declared_p = {"declared_params" => declared(params, include_missing: false)}
            b_param = BParam.new(creator_id: creation_user_id, params: declared_p["declared_params"].as_json, origin: "api_v2")
            b_param.clean_params
            @bike = found_bike
            authorize_bike_for_user

            if b_param.params.dig("bike", "external_image_urls").present?
              @bike.load_external_images(b_param.params["bike"]["external_image_urls"])
            end

            begin
              # Don't update the email (or is_phone), because maybe they have different user emails
              bike_update_params = b_param.params.merge("bike" => b_param.bike.except(:owner_email, :is_phone))
              BikeUpdator
                .new(user: current_user, bike: @bike, b_params: bike_update_params)
                .update_available_attributes
            rescue => e
              error!("Unable to update bike: #{e}", 401)
            end

            status :found
            return created_bike_serialized(@bike.reload, false)
          end

          declared_p = {"declared_params" => declared(params, include_missing: false).merge(creation_state_params)}
          b_param = BParam.new(creator_id: creation_user_id, params: declared_p["declared_params"].as_json, origin: "api_v2")
          b_param.save

          bike = BikeCreator.new.create_bike(b_param)

          if b_param.errors.blank? && b_param.bike_errors.blank? && bike.present? && bike.errors.blank?
            created_bike_serialized(bike, true)
          else
            e = bike.present? ? bike.errors : b_param.errors
            error!(e.full_messages.to_sentence, 401)
          end
        end

        desc "Update a bike owned by the access token<span class='accstr'>*</span>", {
          authorizations: {oauth2: [{scope: :write_bikes}]},
          notes: <<-NOTE
            **Requires** `read_user` **in the access token** you use to send the notification.

            Update a bike owned by the access token you're using.

          NOTE
        }
        params do
          requires :id, type: Integer, desc: "Bike ID"
          use :bike_attrs
          optional :owner_email, type: String, desc: "Send the bike to a new owner!"
          optional :components, type: Array do
            optional :id, type: Integer, desc: "Component ID - if you don't supply this you will create a new component instead of update an existing one"
            use :components_attrs
            optional :destroy, type: Boolean, desc: "Delete this component (requires an ID)"
          end
        end
        put ":id" do
          declared_p = {"declared_params" => declared(params, include_missing: false)}
          find_bike
          authorize_bike_for_user
          b_param = BParam.new(params: declared_p["declared_params"].as_json, origin: "api_v2")
          b_param.clean_params
          hash = b_param.params
          @bike.load_external_images(hash["bike"]["external_image_urls"]) if hash.dig("bike", "external_image_urls").present?
          begin
            BikeUpdator.new(user: current_user, bike: @bike, b_params: hash).update_available_attributes
          rescue => e
            error!("Unable to update bike: #{e}", 401)
          end
          BikeV2ShowSerializer.new(@bike.reload, root: "bike").as_json
        end

        desc "Add an image to a bike", {
          authorizations: {oauth2: [{scope: :write_bikes}]},
          notes: <<-NOTE

            To post a file to the API with curl:

            `curl -X POST -i -F file=@{test_file.jpg} "#{ENV["BASE_URL"]}/api/v3/bikes/{bike_id}/image?access_token={access_token}"`

            Replace `{text_file.jpg}` with the relative path of the file you're posting.

            **RIGHT NOW THIS DEMO DOESN'T WORK.** The `curl` command above does. We're working on the documentation issue, check back soon.

          NOTE
        }
        params do
          requires :id, type: Integer, desc: "Bike ID"
          requires :file, type: Rack::Multipart::UploadedFile, desc: "Attachment."
        end
        post ":id/image" do
          find_bike
          authorize_bike_for_user
          public_image = PublicImage.new(imageable: @bike, image: params[:file])
          if public_image.save
            PublicImageSerializer.new(public_image, root: "image").as_json
          else
            error!(public_image.errors.full_messages.to_sentence, 401)
          end
        end

        desc "Remove an image from a bike", {
          authorizations: {oauth2: [{scope: :write_bikes}]},
          notes: <<-NOTE

            Remove an image from the bike, specifying both the bike_id and the image id (which can be found in the public_images resopnse)

            **Requires** `write_bikes` **in the access token** you use.

          NOTE

        }
        params do
          requires :id, type: Integer, desc: "Bike ID"
          requires :image_id, type: Integer, desc: "Image ID"
        end
        delete ":id/images/:image_id" do
          find_bike
          authorize_bike_for_user
          public_image = @bike.public_images.find_by_id(params[:image_id])
          error!("Unable to find that image", 404) unless public_image.present?
          public_image.destroy
          BikeV2ShowSerializer.new(@bike.reload, root: "bike").as_json
        end

        desc "Send a stolen notification<span class='accstr'>*</span>", {
          authorizations: {oauth2: [{scope: :read_user}]},
          notes: <<-NOTE
            **Requires** `read_user` **in the access token** you use to send the notification.

            <hr>

            Send a stolen bike notification.

            Your application has to be approved to be able to do this. Email support@bikeindex.org to get access.

            Before your application is approved you can send notifications to yourself (to a bike that you own that's stolen).
          NOTE
        }
        params do
          requires :id, type: Integer, desc: "Bike ID. **MUST BE A STOLEN BIKE**"
          requires :message, type: String, desc: "The message you are sending to the owner"
        end
        post ":id/send_stolen_notification" do
          find_bike
          error!("Bike is not stolen", 400) unless @bike.present? && @bike.status_stolen?
          # Unless application is authorized....
          authorize_bike_for_user(" (this application is not approved to send notifications)")
          stolen_notification = StolenNotification.create(bike_id: params[:id],
            message: params[:message],
            sender: current_user)
          StolenNotificationSerializer.new(stolen_notification).as_json
        end
      end
    end
  end
end
