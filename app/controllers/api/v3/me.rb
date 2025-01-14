module API
  module V3
    class Me < API::Base
      include API::V2::Defaults
      resource :me, desc: "Operations about the current user" do
        helpers do
          # Because we respond with unconfirmed users here, provided it's permitted
          def valid_current_user
            return resource_owner if unconfirmed_scope? && resource_owner.present?
            current_user
          end

          def unconfirmed_scope?
            current_scopes.include?("unconfirmed")
          end

          def user_info
            return {} unless current_scopes.include?("read_user")
            {
              user: {
                username: valid_current_user.username,
                name: valid_current_user.name,
                email: valid_current_user.email,
                secondary_emails: valid_current_user.secondary_emails,
                twitter: (valid_current_user.twitter if valid_current_user.show_twitter),
                created_at: valid_current_user.created_at.to_i,
                image: (valid_current_user.avatar_url if valid_current_user.show_bikes)
              }.merge(unconfirmed_scope? ? {confirmed: valid_current_user.confirmed?} : {})
            }
          end

          def bike_ids
            current_scopes.include?("read_bikes") ? {bike_ids: valid_current_user.bike_ids} : {}
          end

          def serialized_membership(membership)
            {
              organization_name: membership.organization.name,
              organization_slug: membership.organization.slug,
              organization_id: membership.organization_id,
              organization_access_token: membership.organization.access_token,
              user_is_organization_admin: membership.role == "admin"
            }
          end

          def organization_memberships
            return {} unless current_scopes.include?("read_organization_membership")
            {memberships: valid_current_user.memberships.map { |m| serialized_membership(m) }}
          end
        end

        desc "Current user's information in access token's scope<span class='accstr'>*</span>", {
          authorizations: {oauth2: []},
          notes: <<-NOTE
            Current user is the owner of the `access_token` you use in the request. Depending on your scopes you will get different things back.
            You will always get the user's `id`
            For an array of the user's bike ids, you need `read_bikes` access
            For a hash of information about the user (including their email address), you need `read_user` access
            For an array of the organizations and/or shops they're a part of, `read_organization_membership` access

          NOTE
        }
        get "/" do
          {id: valid_current_user.id.to_s}.merge(user_info)
            .merge(bike_ids)
            .merge(organization_memberships)
        end

        desc "Current user's bikes<span class='accstr'>*</span>", {
          authorizations: {oauth2: [{scope: :read_bikes}]},
          notes: <<-NOTE
            This returns the current user's bikes, so long as the access_token has the `read_bikes` scope.
            This uses the bike list bike objects, which only contains the most important information.
            To get all possible information about a bike use `/bikes/{id}`

          NOTE
        }
        get "/bikes" do
          ActiveModel::ArraySerializer.new(valid_current_user.bikes,
            each_serializer: BikeV2Serializer,
            root: "bikes").as_json
        end
      end
    end
  end
end
