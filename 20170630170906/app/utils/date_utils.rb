module DateUtils
  module_function

  def from_date_select(hash, name)
    date_arr = [1, 2, 3].map { |i| hash["#{name.to_s}(#{i}i)"].to_i }
    Date.new *date_arr
  end

  def duration_days(start_date, end_date)
    (end_date - start_date).to_i + 1
  end

  def duration_nights(start_date, end_date, minimum_duration)
    # NOTE in MotorHome we calculate duration by counting the nights between dates
    # if there is only one day without a night then duration is 1
    # additionaly owners can determine minimum amount of nigts they are ready to rent for
    duration = (end_date - start_date).to_i
    duration = minimum_duration if duration < minimum_duration
    duration
  end
end
