# frozen_string_literal: true

# Mirrors a Trello card as a conversation on the account's configured WhatsApp
# inbox. The card is the source of the lead: the phone number is parsed from
# the card text and the conversation always lives on WhatsApp.
class Integrations::Trello::WhatsappConversationService
  pattr_initialize [:hook!, :card!, :stage!]

  def perform
    conversation = hook.account.conversations.find_by(trello_card_id: card['id'])
    if conversation
      # Reconnecting a board creates a new pipeline; re-stage existing
      # conversations so the backfill re-maps them onto it.
      conversation.move_to_stage!(stage) unless conversation.pipeline_stage_id == stage.id
      return conversation
    end
    return nil if whatsapp_inbox.blank?

    phone_number = parsed_phone_number
    if phone_number.blank?
      Rails.logger.info("Trello: card #{card['id']} has no parseable phone number; skipping")
      return nil
    end

    conversation = create_conversation(phone_number)
    post_description_note(conversation) if card['desc'].present?
    conversation
  rescue ActiveRecord::RecordNotUnique
    hook.account.conversations.find_by!(trello_card_id: card['id'])
  end

  private

  def create_conversation(phone_number)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: whatsapp_inbox,
      contact_attributes: { name: card['name'], phone_number: phone_number }
    ).perform

    hook.account.conversations.create!(
      inbox: whatsapp_inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox,
      pipeline_stage: stage,
      trello_card_id: card['id'],
      status: :open
    )
  end

  def post_description_note(conversation)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :activity,
        content: I18n.t('conversations.activity.trello.card_description_note', description: card['desc'])
      }
    )
  end

  def parsed_phone_number
    Integrations::Trello::PhoneParser.new(text: [card['name'], card['desc']].compact.join(' ')).perform
  end

  def whatsapp_inbox
    @whatsapp_inbox ||= hook.account.inboxes.find_by(id: hook.settings['whatsapp_inbox_id']).tap do |inbox|
      Rails.logger.warn("Trello: hook #{hook.id} has no valid whatsapp_inbox_id") if inbox.blank?
    end
  end
end
