module TransactionService::Cart
  MOTORHOME_MINIMUM_DURATION = 1

  module_function

  #listing must exist, to get the default fees
  #if transaction exists then get listing from transaction
  #if cart for a transaction exists then load the existing cart
  #once cart is prepared set the new data (pickup/dropoff_location, housekeeping_kit, additional_miles, additional_generator_hours)
  def get_or_create(transaction: nil, listing: nil)
    raise "TransactionService::Cart: must provide listing or transaction to get cart" if transaction.nil? && listing.nil?
    transaction = ::Transaction.find(transaction[:id]) if transaction.is_a? Hash
    cart = transaction.cart if transaction.present? && transaction.cart.present?
    if cart.nil?
      listing = transaction.listing if transaction.present? && !transaction.cart.present?
      cart = initialize(listing: listing)
      if transaction.present?
        cart.assign_attributes({transaction_id: transaction.id, community_id: transaction.community_id})
      end
    end
    cart.save if transaction.present?
    cart
  end

  def initialize(listing: nil)
    listing = Listing.find(listing[:id]) if listing.is_a? Hash
    attributes = attributes_from_listing(listing)
    cart = ::Cart.new(attributes)
  end

  def attributes_from_listing(listing)
    field_values = {}
    field_values[:currency] = listing.currency

    field_name_to_custom_field = {
      additional_miles_price_per_mile: {custom_field_id: 23753, action: :extract_money},
      generator_hours_price_per_hour: {custom_field_id: 23736, action: :extract_money},
      cleaning_fee: {custom_field_id: 23738, action: :extract_money},
      housekeeping_kit_price: {custom_field_id: 23743, action: :extract_money},
      dump_water_fee: {custom_field_id: 23739, action: :extract_money},
      security_deposit: {custom_field_id: 18830, action: :extract_money},
      delivery_fee_per_mile: {custom_field_id: 23740, action: :ensure_string},
      cancellation_policy: {custom_field_id: 18380, action: :ensure_string},
      minimum_duration: {custom_field_id: 19549, action: :extract_minimum_duration},
      included_miles_per_day: {custom_field_id: 23754, action: :ensure_integer},
      included_generator_hours_per_day: {custom_field_id: 23755, action: :ensure_integer}
    }

    field_name_to_custom_field.each do |key, data|
      object = listing.custom_field_values
        .where(listing_id: listing.id, custom_field_id: data[:custom_field_id]).first
      #retrieve data
      field_values[key] = object.text_value if object.is_a? TextFieldValue
      field_values[key] = object.numeric_value if object.is_a? NumericFieldValue
      field_values[key] = CustomFieldOptionTitle.where(custom_field_option_id: CustomFieldOptionSelection.where(custom_field_value_id: object.id).first.custom_field_option_id).first.value if object.is_a? DropdownFieldValue
      #process data
      field_values[key] = send(data[:action], field_values[key]) unless field_values[key].nil?
    end

    field_values
  end

  def extract_money(str)
    str = "" if str.nil?
    str = str.delete(',')
    str = str.scan(/([$\d.]+)/)
    str = str.try(:first).try(:first)
    str.nil? ? Money.new(0, 'USD') : str.to_money
  end

  def extract_minimum_duration(str)
    str = "" if str.nil?
    str = str.scan(/(\d+)/)
    str = str.try(:first).try(:first)
    minimum_duration = str.to_i
    minimum_duration = MOTORHOME_MINIMUM_DURATION if minimum_duration < MOTORHOME_MINIMUM_DURATION
    minimum_duration
  end

  def ensure_string(str)
    str.to_s
  end

  def ensure_integer(number)
    number
  end

  # additional_miles
  def calculate_additional_miles(total_miles, cart, duration)
    if total_miles
      total_miles = total_miles.to_i
      miles_included = calculate_included_miles(cart, duration)
      additional_miles = total_miles - miles_included
      (additional_miles > 0 ? additional_miles : 0)
    else
      0
    end
  end

  # total_miles
  def calculate_total_miles(cart, duration)
    additional_miles = cart.additional_miles
    miles_included = calculate_included_miles(cart, duration)
    additional_miles + miles_included
  end

  # included_miles
  def calculate_included_miles(cart, duration)
    included_miles_per_day = cart.included_miles_per_day.to_i
    included_miles_per_day * duration
  end

  # additional_generator_hours
  def calculate_additional_generator_hours(total_generator_hours, cart, duration)
    if total_generator_hours
      total_generator_hours = total_generator_hours.to_i
      hours_included = calculate_included_generator_hours(cart, duration)
      additional_generator_hours = total_generator_hours - hours_included
      (additional_generator_hours > 0 ? additional_generator_hours : 0)
    else
      0
    end
  end

  # total_generator_hours
  def calculate_total_generator_hours(cart, duration)
    additional_hours = cart.additional_generator_hours
    hours_included = calculate_included_generator_hours(cart, duration)
    additional_hours + hours_included
  end

  # included_generator_hours
  def calculate_included_generator_hours(cart, duration)
    included_generator_hours_per_day = cart.included_generator_hours_per_day.to_i
    included_generator_hours_per_day * duration
  end

  def calculate_duration(booking_start_on, booking_end_on, cart)
    minimum_duration = cart.minimum_duration
    DateUtils.duration_nights(booking_start_on, booking_end_on, minimum_duration)
  end

end

