module FitbitApiHelper
  def random_data data_type
    case data_type
    when :activity_name
      ['biking', 'jogging', 'yoga', 'jazzercise'].sample
    when :date_range
      base_date = Date.today
      end_date = base_date + rand(365)
      [base_date, end_date].map { |day| day.strftime('%Y-%m-%d').squeeze(' ') }
    when :fitbit_id
      length = 7
      ([*('A'..'Z'),*('0'..'9')]-%w(0 1 I O)).sample(length).join
    when :fixed_date
      today = Date.today
      today.strftime('%Y-%m-%d').squeeze(' ')
    when :period
      number_of = rand(31)
      types = ['d', 'w', 'm']
      [number_of, types.sample(1)].join
    when :response_format
      random_format = ['json', 'xml'].sample
    when :resource_path
      resource_paths = [
        'activities/calories',
        'body/weight',
        'foods/log/caloriesIn',
        'sleep/startTime'
      ]
      resource_paths.sample
    when :time
      current_time = Time.now
      current_time.strftime('%H:%M').squeeze(' ')
    when :time_range
      start_time = Time.now
      end_time = start_time + (60 * 60 * rand(12))
      [start_time, end_time].map { |time| time.strftime('%H:%M').squeeze(' ') }
    when :token
      length = 30
      rand(36**length).to_s(36)
    end
  end

  def helpful_errors api_method, error_type, required="", supplied=""
    api_method.downcase!

    case error_type
    when 'post_parameters'
      error = "requires POST parameters #{required}. You're missing #{required - supplied}."
    when 'dynamic-url'
      total = required.length
      options = required.each_with_index.map { |x,i| "(#{i+1}) #{x}" }.join(' ')
      error = "requires 1 of #{total} options: #{options}. You supplied: #{supplied}."
    when 'exclusive_too_many'
      extra_data = required.join(' AND ')
      error = "allows only one of these POST parameters: #{required}. You used #{extra_data}."
    when 'exclusive_too_few'
      error = "requires one of these POST parameters: #{required}."
    when 'required_if'
      error = "requires POST parameter #{required} when you use POST parameter #{supplied}."
    when 'one_required'
      error = "requires at least one of the following POST parameters: #{required}."
    when 'url_parameters'
      error = "requires #{required}. You\'re missing #{required - supplied}."
    when 'resource_path'
      error = get_resource_path_error(supplied)
    when 'invalid'
      error = "is not a valid Fitbit API method."
    end
    "#{api_method} " + error
  end
    
  def oauth_unauthenticated http_method, api_url, consumer_key, consumer_secret, params
    stub_request(http_method, "api.fitbit.com#{api_url}")
    api_call = subject.api_call(consumer_key, consumer_secret, params)
    expect(api_call.class).to eq(Net::HTTPOK)
  end
    
  def oauth_authenticated http_method, api_url, consumer_key, consumer_secret, params, auth_token, auth_secret
    stub_request(http_method, "api.fitbit.com#{api_url}")
    api_call = subject.api_call(consumer_key, consumer_secret, params, auth_token, auth_secret)
    expect(api_call.class).to eq(Net::HTTPOK)
  end

  def get_url_with_post_parameters url, params, ignore
    params.delete_if { |k,v| ignore.include? k }
    url + "?" + OAuth::Helper.normalize(params)
  end
end
