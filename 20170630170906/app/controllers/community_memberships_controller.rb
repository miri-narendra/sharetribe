class CommunityMembershipsController < ApplicationController

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_this_page")
  end

  skip_filter :cannot_access_if_banned
  skip_filter :cannot_access_without_confirmation
  skip_filter :ensure_consent_given
  skip_filter :ensure_user_belongs_to_community

  before_filter :ensure_membership_found
  before_filter :ensure_membership_is_not_accepted
  before_filter only: [:pending_consent, :give_consent] {
    ensure_membership_status("pending_consent")
  }
  before_filter only: [:confirmation_pending] {
    ensure_membership_status("pending_email_confirmation")
  }

  Form = EntityUtils.define_builder(
    [:invitation_code, :string],
    [:email, :string],
    [:phone_number, :string],
    [:is_owner, one_of: [nil, "false", "true"]],
    [:consent, one_of: [nil, "on"]]
  )

  def pending_consent
    render_pending_consent_form(invitation_code: session[:invitation_code], phone: "", is_owner: "false")
  end

  def give_consent
    form_params = params[:form] || {}
    values = Form.call(form_params)

    invitation_check = ->() {
      if @current_community.join_with_invite_only?
        validate_invitation_code(invitation_code: values[:invitation_code],
                                 community: @current_community)
      else
        Result::Success.new()
      end
    }
    email_check = ->(_) {
      if @current_user.has_valid_email_for_community?(@current_community)
        Result::Success.new()
      else
        validate_email(address: values[:email],
                       community: @current_community,
                       user: @current_user)
      end
    }
    terms_check = ->(_, _) {
      validate_terms(consent: values[:consent], community: @current_community)
    }
    phone_number_check = ->(_, _, _) {
      validate_phone_number(phone_number: values[:phone_number])
    }
    is_owner_check = -> (_, _, _, _) {
      is_owner = (values[:is_owner] == "true")
      validate_is_owner(is_owner: is_owner)
    }

    check_result = Result.all(invitation_check, email_check, terms_check, phone_number_check, is_owner_check)

    check_result.and_then { |invitation_code, email_address, consent, phone_number, is_owner|
      @current_user.update_attribute :phone_number, phone_number
      update_membership!(membership: membership,
                         invitation_code: invitation_code,
                         email_address: email_address,
                         consent: consent,
                         is_owner: is_owner,
                         community: @current_community,
                         user: @current_user)
    }.on_success {

      # Cleanup session
      session[:fb_join] = nil
      session[:invitation_code] = nil

      Delayed::Job.enqueue(CommunityJoinedJob.new(@current_user.id, @current_community.id))
      Delayed::Job.enqueue(CreateSalesforceLeadJob.new(@current_user.id, @current_community.id)) if @current_community
      Delayed::Job.enqueue(SendWelcomeEmail.new(@current_user.id, @current_community.id), priority: 5)

      flash[:notice] = t("layouts.notifications.you_are_now_member")
      if session[:return_to]
        redirect_to session[:return_to]
        session[:return_to] = nil
      elsif session[:return_to_content]
        redirect_to session[:return_to_content]
        session[:return_to_content] = nil
      else
        redirect_to search_path
      end

    }.on_error { |msg, data|

      case data[:reason]

      when :invitation_code_invalid_or_used
        flash[:error] = t("community_memberships.give_consent.invitation_code_invalid_or_used")
        logger.info("Invitation code was invalid or used", :membership_email_not_allowed, data)
        render_pending_consent_form(values.except(:invitation_code))

      when :email_not_allowed
        flash[:error] = t("community_memberships.give_consent.email_not_allowed")
        logger.info("Email is not allowed", :membership_email_not_allowed, data)
        render_pending_consent_form(values.except(:email))

      when :email_not_available
        flash[:error] = t("community_memberships.give_consent.email_not_available")
        logger.info("Email is not available", :membership_email_not_available, data)
        render_pending_consent_form(values.except(:email))

      when :invalid_phone_number
        flash[:error] = t("people.new.invalid_phone_number")
        logger.info("Invalid phone number", :membership_invalid_phone_number, data)
        render_pending_consent_form(values)

      when :invalid_is_owner
        flash[:error] = t("people.new.invalid_is_owner")
        logger.info("Please select if you whish to register as owner or renter", :membership_invalid_is_owner, data)
        render_pending_consent_form(values)

      when :consent_not_given
        flash[:error] = t("community_memberships.give_consent.consent_not_given")
        logger.info("Terms were not accepted", :membership_consent_not_given, data)
        render_pending_consent_form(values.except(:consent))

      when :update_failed
        flash[:error] = t("layouts.notifications.joining_community_failed")
        logger.info("Membership update failed", :membership_update_failed, data)
        render_pending_consent_form(values)

      else
        raise ArgumentError.new("Unhandled error case: #{data[:reason]}")
      end
    }
  end

  def confirmation_pending
  end

  # Ajax end-points for front-end validation

  def check_email_availability_and_validity
    values = Form.call(params[:form])
    validation_result = validate_email(address: values[:email],
                                       user: @current_user,
                                       community: @current_community)

    render json: validation_result.success
  end

  def check_phone_number_validity
    values = Form.call(params[:form])
    validation_result = validate_phone_number(phone_number: values[:phone_number])

    render json: validation_result.success
  end

  def check_invitation_code
    values = Form.call(params[:form])
    validation_result = validate_invitation_code(invitation_code: values[:invitation_code],
                                                 community: @current_community)

    render json: validation_result.success
  end

  def access_denied
    # Nothing here, just render the access_denied.haml
  end

  private

  def render_pending_consent_form(form_values = {})
    values = Form.call(form_values)
    invite_only = @current_community.join_with_invite_only?
    allowed_emails = Maybe(@current_community.allowed_emails).split(",").or_else([])

    render :pending_consent, locals: {
             invite_only: invite_only,
             allowed_emails: allowed_emails,
             has_valid_email_for_community: @current_user.has_valid_email_for_community?(@current_community),
             values: values
           }
  end

  def validate_email(address:, community:, user:)
    if !community.email_allowed?(address)
      Result::Error.new("Email is not allowed", reason: :email_not_allowed, email: address)
    elsif !Email.email_available?(address, community.id)
      Result::Error.new("Email is not available", reason: :email_not_available, email: address)
    else
      Result::Success.new(address)
    end
  end

  def validate_phone_number(phone_number:)
    if !!(phone_number =~ PeopleController::PHONE_NUMBER_FORMAT)
      Result::Success.new(phone_number)
    else
      Result::Error.new("Ivalid phone number", reason: :invalid_phone_number)
    end
  end

  def validate_is_owner(is_owner:)
    if [false, true].include?(is_owner)
      Result::Success.new(is_owner)
    else
      Result::Error.new("Select if you wish to register as owner or renter", reason: :invalid_is_owner)
    end
  end

  def validate_invitation_code(invitation_code:, community:)
    if !Invitation.code_usable?(invitation_code, community)
      Result::Error.new("Invitation code is not usable", reason: :invitation_code_invalid_or_used, invitation_code: invitation_code)
    else
      Result::Success.new(invitation_code.upcase)
    end
  end

  def validate_terms(consent:, community:)
    if consent == "on"
      Result::Success.new(community.consent)
    else
      Result::Error.new("Consent not accepted", reason: :consent_not_given)
    end
  end

  def update_membership!(membership:, invitation_code:, email_address:, consent:, is_owner:, user:, community:)
    make_admin = community.members.count == 0 # First member is the admin

    begin
      ActiveRecord::Base.transaction do
        if email_address.present?
          Email.create!(person_id: user.id, address: email_address, community_id: community.id)
        end

        m_invitation = Maybe(invitation_code).map { |code| Invitation.find_by(code: code) }
        m_invitation.each { |invitation|
          invitation.use_once!
        }

        attrs = {
          consent: consent,
          is_owner: is_owner,
          invitation: m_invitation.or_else(nil),
          status: "accepted"
        }

        attrs[:admin] = true if make_admin

        membership.update_attributes!(attrs)
      end

      Result::Success.new(membership)
    rescue
      Result::Error.new("Updating membership failed", reason: :update_failed, errors: membership.errors.full_messages)
    end
  end

  def report_missing_membership(user, community)
    ArgumentError.new("User doesn't have membership. Don't know how to continue. person_id: #{user.id}, community_id: #{community.id}")
  end

  def membership
    @membership ||= @current_user.community_membership
  end

  # Filters

  def ensure_membership_found
    report_missing_membership(@current_user, @current_community) if membership.nil?
  end

  def ensure_membership_is_not_accepted
    if membership.accepted?
      flash[:notice] = t("layouts.notifications.you_are_already_member")
      redirect_to search_path
    end
  end

  def ensure_membership_status(status)
    raise ArgumentError.new("Unknown state #{status}") unless CommunityMembership::VALID_STATUSES.include?(status)

    if membership.status != status
      redirect_to search_path
    end
  end
end
