class Admin::CommunityListingsController < ApplicationController
  before_filter :ensure_is_admin

  def index
    @selected_left_navi_link = "manage_listings"
    @community = @current_community

    respond_to do |format|
      format.html do
        @listings = Listing.where(community_id: @current_community.id, is_approved: false)
                                           .includes(author: :emails)
                                           .paginate(page: params[:page], per_page: 50)
                                           .order("#{sort_column} #{sort_direction}")
      end
    end
  end

  def approve
    listing= Listing.find_by_id(params[:id])

    listing.update_attribute(:is_approved, true)
    listing.update_attribute(:open, true)

    if listing.open?
      flash[:notice] = t('admin.communities.manage_listings.published')
    else
      flash[:error] = t('admin.communities.manage_listings.could_not_publish')
    end
    redirect_to admin_community_community_listings_path(@current_community)
  end

  private

  def sort_column
    case params[:sort]
    when "owner_name"
      "people.given_name"
    when "owner_email"
      "emails.address"
    when "create_date"
      "created_at"
    when "title"
      "title"
    else
      "created_at"
    end
  end

  def sort_direction
    #prevents sql injection
    if params[:direction] == "asc"
      "asc"
    else
      "desc" #default
    end
  end

end
