# frozen_string_literal: true

module Providers
  # Contract cho calendar provider (Google/Outlook OAuth — P1 khi có credential).
  class CalendarProviderAdapter
    def push_event(event) = raise NotImplementedError
    def list_events(from:, to:) = raise NotImplementedError
    def provider_name = self.class.name.demodulize
  end
end
