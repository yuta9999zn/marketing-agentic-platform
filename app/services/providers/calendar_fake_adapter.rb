# frozen_string_literal: true

module Providers
  # Fake calendar: chỉ render ICS string — đủ cho MVP export/preview.
  class CalendarFakeAdapter < CalendarProviderAdapter
    def push_event(event)
      { "ok" => true, "mode" => "fake", "ics_bytes" => event.to_ics.bytesize }
    end

    def list_events(from:, to:)
      Event.where(starts_at: from..to).order(:starts_at)
    end

    def provider_name = "calendar_fake"
  end
end
