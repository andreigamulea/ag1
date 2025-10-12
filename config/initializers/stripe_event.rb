StripeEvent.configure do |events|
    events.subscribe 'charge.failed' do |event|
      # Define subscriber behavior based on the event object that will be passed
      # to this block.
    end
  end