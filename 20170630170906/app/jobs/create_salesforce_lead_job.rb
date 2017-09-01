class CreateSalesforceLeadJob < Struct.new(:person_id, :community_id)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have host parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    #user = APP_CONFIG.salesforce_username
    #pass = APP_CONFIG.salesforce_password
    #sec_token = APP_CONFIG.salesforce_security_token
    #client_id = APP_CONFIG.salesforce_client_id
    #client_secret = APP_CONFIG.salesforce_client_secret
    #api_version = APP_CONFIG.salesforce_api_version
    #client = Restforce.new(
    #  username: user,
    #  password: pass,
    #  security_token: sec_token,
    #  client_id: client_id,
    #  client_secret: client_secret,
    #  api_version: api_version,
    #  host: 'eu11.salesforce.com'
    #)
    #account = client.find('Account', '0010Y000009cWnK')
    #
    #<!--  ----------------------------------------------------------------------  -->
    #<!--  NOTE: These fields are optional debugging elements. Please uncomment    -->
    #<!--  these lines if you wish to test in debug mode.                          -->
    #<!--  <input type="hidden" name="debug" value=1>                              -->
    #<!--  <input type="hidden" name="debugEmail" value="valdis@ithouse.lv">       -->
    #<!--  ----------------------------------------------------------------------  -->
    current_community = Community.find(community_id)
    new_user = Person.find(person_id)

    uri = URI(APP_CONFIG.salesforce_webtolead_url )
    res = Net::HTTP.post_form(uri, {
      "oid" => APP_CONFIG.salesforce_webtolead_oid, # not sure is this form id or user id
      "retURL" => "https://privatemotorhomerental.com", # return url
      "first_name" => new_user.given_name,
      "last_name" => new_user.family_name,
      "email" => new_user.emails.last.address,
      "phone" => new_user.phone_number,
      APP_CONFIG.salesforce_webtolead_is_owner_field_id => (new_user.is_owner? ? "1" : "0") # custom field id for "is owner field"
    })
    Delayed::Worker.logger.info("Salesforce lead created for: #{new_user.emails.last.address}; status #{res.class.to_s}")
  end

end
