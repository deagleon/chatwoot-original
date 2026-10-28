# Fuso da conta (settings.reporting_timezone), com UTC como fallback padrão.
account_timezone = scheduled_message.account.reporting_timezone.presence || 'UTC'
json.id scheduled_message.id
json.content scheduled_message.content
json.scheduled_at scheduled_message.scheduled_at.in_time_zone(account_timezone).iso8601
json.status scheduled_message.status
json.internal_note scheduled_message.internal_note
json.message_id scheduled_message.message_id
json.sent_at scheduled_message.sent_at&.in_time_zone(account_timezone)&.iso8601
json.error scheduled_message.error
json.created_by scheduled_message.created_by.push_event_data if scheduled_message.created_by
