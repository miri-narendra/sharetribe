require 'spec_helper'

describe HomepageController, type: :controller do

  describe "selected view type" do

    it "returns param view type if param is present and it is one of the view types, otherwise comm default" do
      types = ["map", "list", "grid"]
      expect(HomepageController.selected_view_type("map", "list", "grid", types)).to eq("map")
      expect(HomepageController.selected_view_type(nil, "list", "grid", types)).to eq("list")
      expect(HomepageController.selected_view_type("", "list", "grid", types)).to eq("list")
      expect(HomepageController.selected_view_type("not_existing_view_type", "list", "grid", types)).to eq("list")
    end

    it "defaults to app default, if comm default is incorrect" do
      types = ["map", "list", "grid"]
      expect(HomepageController.selected_view_type("", "list", "grid", types)).to eq("list")
      expect(HomepageController.selected_view_type("", nil, "grid", types)).to eq("grid")
      expect(HomepageController.selected_view_type("", "", "grid", types)).to eq("grid")
      expect(HomepageController.selected_view_type("", "not_existing_view_type", "grid", types)).to eq("grid")
    end

  end

  describe "custom field options for search" do

    it "returns ids in correct order" do
      @custom_field1 = FactoryGirl.create(:custom_dropdown_field)
      @custom_field2 = FactoryGirl.create(:custom_dropdown_field)
      @custom_field_option1 = FactoryGirl.create(:custom_field_option, :custom_field =>  @custom_field1)
      @custom_field_option2 = FactoryGirl.create(:custom_field_option, :custom_field =>  @custom_field1)
      @custom_field_option3 = FactoryGirl.create(:custom_field_option, :custom_field =>  @custom_field2)
      @custom_field_option4 = FactoryGirl.create(:custom_field_option, :custom_field =>  @custom_field2)

      array = HomepageController.dropdown_field_options_for_search({
        "filter_options_#{@custom_field_option1.id}" => @custom_field_option1.id,
        "filter_options_#{@custom_field_option2.id}" => @custom_field_option2.id,
        "filter_options_#{@custom_field_option3.id}" => @custom_field_option3.id,
        "filter_options_#{@custom_field_option4.id}" => @custom_field_option4.id
      })

      expect(array).to eq([
        {id: @custom_field1.id, value: [@custom_field_option1.id, @custom_field_option2.id]},
        {id: @custom_field2.id, value: [@custom_field_option3.id, @custom_field_option4.id]},
      ])
    end

  end

  context 'Listing by location', 'no-transaction': true do
    let(:community) { community = create :community, domain: 'test.org', use_domain: true
      create :marketplace_configurations, community_id: community.id
      community
    }
    let!(:person) { create :person, community_id: community.id }
    let!(:community_membership) { create :community_membership, community: community, person: person }
    let!(:listing_shape) { create :listing_shape, community_id: community.id }
    let(:listing_1) { create :listing, title: 'New York', author: person, community_id: community.id }
    let(:location_1) do
      create :location, {
        listing: listing_1,
        person: person,
        community: community,
        location_type: 'origin_loc',
        latitude: 40.712784,
        longitude: (-74.005941),
        address: 'New York',
        google_address: 'New York, NY, United States'
      }
    end

    let(:listing_2) { create :listing, title: 'Green Bay', author: person, community_id: community.id }
    let(:location_2) do
      create :location, {
        listing: listing_2,
        person: person,
        community: community,
        location_type: 'origin_loc',
        latitude: 44.519159,
        longitude: (-88.019826),
        address: 'Green Bay',
        google_address: 'Green Bay, WI, United States'
      }
    end

    let(:query_vancouver) {{"view":"grid","q":"Vancouver, BC, Canada","lc":"49.282729,-123.120738","ls":"OK","boundingbox":"49.198177,-123.224759,49.314076,-123.023068","distance_max":"9.751228782518787"}}
    let(:query_new_york) {{"view":"grid","q":"New York, NY, United States","lc":"40.712784,-74.005941","ls":"OK","boundingbox":"40.496044,-74.255735,40.915256,-73.700272","distance_max":"33.03459434957673"}}

    before :each do
      @request.host = 'test.org'
      @request.env[:current_marketplace] = community
      location_1
      location_2
      sphinx_ensure_is_running_and_indexed
    end

    it 'search for Vancouver' do
      post :index, query_vancouver
      listings = assigns(:listings)
      expect(listings.size).to eq 2
      expect(listings.first.id).to eq listing_2.id
    end

    it 'search for New York' do
      post :index, query_new_york
      listings = assigns(:listings)
      expect(listings.size).to eq 2
      expect(listings.first.id).to eq listing_1.id
    end
  end

end
