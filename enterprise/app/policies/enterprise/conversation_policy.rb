module Enterprise::ConversationPolicy
  def show?
    return false unless super
    return true unless custom_role_permissions?

    permissions = custom_role_permissions
    return true if manage_all_conversations?(permissions)
    return true if permits_unassigned_manage?(permissions)

    permits_participating?(permissions)
  end

  # Ações de escrita de conversa (ex.: mover de etapa — authorize :update?)
  # seguem o modelo de custom roles do show?, com uma exceção: o caminho
  # participating (atribuição/participação) é a própria autorização e dispensa o
  # inbox access — sem isso, o agente atribuído não moveria (caso OND-134).
  # Permissões amplas (manage_all/unassigned_manage) NÃO são atreladas a uma
  # relação com a conversa e continuam exigindo o acesso-base do OSS
  # (inbox/team/admin/bot) — o escopo por inbox não pode ser furado: um agente
  # com conversation_manage de um inbox não move conversas de outro inbox.
  def update?
    return super unless custom_role_permissions?

    permissions = custom_role_permissions
    return true if permits_participating?(permissions)
    return false unless super

    manage_all_conversations?(permissions) || permits_unassigned_manage?(permissions)
  end

  private

  def manage_all_conversations?(permissions)
    permissions.include?('conversation_manage')
  end

  def permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')

    unassigned_conversation? || assigned_to_user?
  end

  def permits_participating?(permissions)
    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  def unassigned_conversation?
    record.assignee_id.nil? && record.assignee_agent_bot_id.nil?
  end

  def custom_role_permissions?
    account_user&.custom_role_id.present?
  end

  def custom_role_permissions
    account_user&.custom_role&.permissions || []
  end
end
