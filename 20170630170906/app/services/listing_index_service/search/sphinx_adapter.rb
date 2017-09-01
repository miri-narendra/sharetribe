module ListingIndexService::Search

  class SphinxAdapter < SearchEngineAdapter

    # http://pat.github.io/thinking-sphinx/advanced_config.html
    SPHINX_MAX_MATCHES = 1000

    INCLUDE_MAP = {
      listing_images: :listing_images,
      author: :author,
      num_of_reviews: {author: :received_testimonials},
      location: :location
    }

    def search(community_id:, search:, includes:)
      included_models = includes.map { |m| INCLUDE_MAP[m] }

      # rename listing_shape_ids to singular so that Sphinx understands it
      search = HashUtils.rename_keys({:listing_shape_ids => :listing_shape_id}, search)

      if DatabaseSearchHelper.needs_db_query?(search) && DatabaseSearchHelper.needs_search?(search)
        return Result::Error.new(ArgumentError.new("Both DB query and search engine would be needed to fulfill the search"))
      end

      if DatabaseSearchHelper.needs_search?(search)
        if search_out_of_bounds?(search[:per_page], search[:page])
          DatabaseSearchHelper.success_result(0, [], includes)
        else
          search_with_sphinx(community_id: community_id,
                             search: search,
                             included_models: included_models,
                             includes: includes)
        end
      else
        DatabaseSearchHelper.fetch_from_db(community_id: community_id,
                                           search: search,
                                           included_models: included_models,
                                           includes: includes)
      end
    end

    private

    def search_with_sphinx(community_id:, search:, included_models:, includes:)
      numeric_search_fields = search[:fields].select { |f| f[:type] == :numeric_range }
      perform_numeric_search = numeric_search_fields.present?

      numeric_search_match_listing_ids =
        if numeric_search_fields.present?
          numeric_search_params = numeric_search_fields.map { |n|
            { custom_field_id: n[:id], numeric_value: n[:value] }
          }
          NumericFieldValue.search_many(numeric_search_params).collect(&:listing_id)
        else
          []
        end

      if perform_numeric_search && numeric_search_match_listing_ids.empty?
        # No matches found with the numeric search
        # Do a short circuit and return emtpy paginated collection of listings wrapped into a success result
        DatabaseSearchHelper.success_result(0, [], nil)
      else

        with = HashUtils.compact(
          {
            community_id: community_id,
            category_id: search[:categories], # array of accepted ids
            listing_shape_id: search[:listing_shape_id],
            price_cents: search[:price_cents],
            listing_id: numeric_search_match_listing_ids,
          })

        selection_groups = search[:fields].select { |v| v[:type] == :selection_group }
        grouped_by_operator = selection_groups.group_by { |v| v[:operator] }

        with_all = {
          custom_dropdown_field_options: (grouped_by_operator[:or] || []).map { |v| v[:value] },
          custom_checkbox_field_options: (grouped_by_operator[:and] || []).flat_map { |v| v[:value] },
        }

        input_latitude = search[:latitude]
        input_longitude = search[:longitude]
        if input_latitude.present? && input_longitude.present?
          # distance in miles, but it can be easily converted to meters by doing distance*1609.
          multiplier = search[:distance_unit] == :km ? 1.609 : 1
          sphinx_select = "*, SQRT(69.1*69.1*(latitude_deg - #{input_latitude})*(latitude_deg - #{input_latitude}) + 53*53*(longitude_deg - #{input_longitude})*(longitude_deg - #{input_longitude})) as distance"
          db_select = "listings.*, #{multiplier}*SQRT(69.1*69.1*(locations.latitude - #{input_latitude})*(locations.latitude - #{input_latitude}) + 53*53*(locations.longitude - #{input_longitude})*(locations.longitude - #{input_longitude})) as distance, '#{search[:distance_unit]}' as distance_unit"
        else
          sphinx_select = '*, 1 as distance'
          db_select = 'listings.*, NULL as distance, NULL as distance_unit'
        end
        #origin_loc_join = "LEFT JOIN `locations` ON `locations`.`listing_id` = `listings`.`id` AND (location_type = 'origin_loc')"
        origin_loc_join = [:origin_loc]

        models = Listing.search(
          Riddle::Query.escape(search[:keywords] || ""),
          select: sphinx_select,
          sql: {
            select: db_select,
            include: included_models,
            joins: [origin_loc_join]
          },
          page: search[:page],
          per_page: search[:per_page],
          star: true,
          with: with,
          with_all: with_all,
          order: 'distance ASC, sort_date DESC',
          max_query_time: 1000 # Timeout and fail after 1s
        )

        begin
          DatabaseSearchHelper.success_result(models.total_entries, models, includes)
        rescue ThinkingSphinx::SphinxError => e
          Result::Error.new(e)
        end
      end

    end

    def search_out_of_bounds?(per_page, page)
      pages = (SPHINX_MAX_MATCHES.to_f / per_page.to_f)
      page > pages.ceil
    end

    def selection_groups(groups)
      if groups[:search_type] == :and
        groups[:values].flatten
      else
        groups[:values]
      end
    end
  end
end
