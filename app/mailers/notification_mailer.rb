class NotificationMailer < ActionMailer::Base
  default :from => ENV['STORY_BUILDER_FROM_EMAIL']
	layout 'mailer'

  def send_new_user(message)
    @message = message
    mail(:bcc => "#{message.bcc}",
         :subject => I18n.t("mailer.notification.new_user.subject"))    
  end
  def send_published_story(message)
    @message = message
    mail(:to => "#{message.email}",
         :subject => I18n.t("mailer.notification.published_story.subject"))    
  end
  def send_story_comment(message)
    @message = message
    mail(:to => "#{message.email}",
         :subject => I18n.t("mailer.notification.story_comment.subject"))    
  end
  def send_published_news(message)
    @message = message
    mail(:bcc => "#{message.bcc}",
         :subject => I18n.t("mailer.notification.published_news.subject"))    
  end
  def send_staff_pick_review(message)
    @message = message
    mail(:bcc => "#{message.bcc}",
			:subject => I18n.t("mailer.notification.staff_pick_review.subject"))
  end
  def send_staff_pick_selection(message)
    @message = message
    mail(:to => "#{message.email}",
			:subject => I18n.t("mailer.notification.staff_pick_selection.subject"))
  end
  def send_story_collaboration(message)
    @message = message
    mail(:to => "#{message.email}",
			:subject => I18n.t("mailer.notification.story_collaboration.subject"))
  end
  def send_processed_videos(message)
    @message = message
    mail(:to => "#{message.email}",
			:subject => I18n.t("mailer.notification.processed_videos.subject"))
  end
  def send_processed_video_errors(message)
    @message = message
    mail(:bcc => "#{message.bcc}",
			:subject => I18n.t("mailer.notification.processed_video_errors.subject"))
  end

end
