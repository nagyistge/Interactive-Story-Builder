class Story < ActiveRecord::Base
  include TranslationOverride

  @@TYPE = {story: 1, talk_show: 2, video: 3, photo: 4, infographic: 5}

	translates :shortened_url, :title, :permalink, :permalink_staging, :author, :media_author, :about, 
              :published, :published_at, :language_type, :translation_percent_complete, :translation_author

  # for likes
  acts_as_votable
  
  # tagging system
  acts_as_taggable
  
  # fields to search for in a story
  scoped_search :in => :story_translations, :on => [:title, :author, :media_author, :translation_author]
  scoped_search :in => :content, :on => [:caption, :sub_caption, :content]

  # record public views
  is_impressionable :counter_cache => true 

  has_many :story_translations, :dependent => :destroy
  has_many :invitations, :dependent => :destroy
	has_many :story_categories
	has_many :categories, :through => :story_categories, :dependent => :destroy
  has_many :story_themes
  has_many :themes, :through => :story_themes, :dependent => :destroy
	belongs_to :user
  belongs_to :language, :primary_key => :locale, :foreign_key => :story_locale
	belongs_to :template
  belongs_to :story_type
	has_many :sections, :order => 'position', dependent: :destroy
	has_and_belongs_to_many :users
	has_one :asset,     
	  :conditions => "asset_type = #{Asset::TYPE[:story_thumbnail]}", 	 
	  foreign_key: :item_id,
	  dependent: :destroy
	has_many :content, :through => :sections

	accepts_nested_attributes_for :asset, :reject_if => lambda { |c| c[:asset].blank? }
  accepts_nested_attributes_for :story_translations

  attr_reader :tag_list_tokens
  attr_accessor :send_notification, :send_staff_pick_notification, :send_comment_notification

  DEMO_ID = 2

  LANGUAGE_TYPE = {:primary => 0, :translation => 1}
  
  
  #################################
  ## Validations
  validates :story_type_id, :presence => true
	validates :template_id, :presence => true
	validates :story_locale, :presence => true 

  #################################
  ## Callbacks

	before_save :generate_reviewer_key

  # if the reviewer key does not exist, create it
  def generate_reviewer_key
    if self.reviewer_key.blank?
      self.reviewer_key = Random.new.rand(100_000_000..1_000_000_000-1)
    end
    return true
  end


  #################################
  ## Scopes
  # scope :recent, joins(:story_translations).order("story_translations.published_at desc, story_translations.title asc")
  # scope :reads, joins(:story_translations).order("stories.impressions_count desc, story_translations.published_at desc, story_translations.title asc")
  # scope :likes, joins(:story_translations).order("stories.cached_votes_total desc, story_translations.published_at desc, story_translations.title asc")
  # scope :comments, joins(:story_translations).order("stories.comments_count desc, story_translations.published_at desc, story_translations.title asc")

	scope :is_not_published, joins(:story_translations).where(:story_translations => {:published => false})
	scope :is_published, joins(:story_translations).where(:story_translations => {:published => true})
  scope :stories_by_author, -> (user_id) {
    where(:user_id => user_id, :published => true).recent
  }

# SELECT a.*
# FROM parallax_chca.stories AS a LEFT JOIN parallax_chca.stories AS b
# ON (a.story_type_id = b.story_type_id AND a.published_at < b.published_at)
# WHERE b.published_at IS NULL and a.story_type_id is not null and a.published = 1;

  scope :recent_by_type, joins("LEFT JOIN stories b ON `stories`.story_type_id = b.story_type_id and `stories`.published_at < b.published_at").where("`stories`.published = true and b.published_at is null").order("`stories`.story_type_id")
  
  # since there can be many language records for a story (thus many published_at dates, titles, etc), it is possible to get duplicate records for a story
  # so must use the uniq method
  def self.recent
    joins(:story_translations).order("story_translations.published_at desc, story_translations.title asc").uniq
  end
  def self.reads
    joins(:story_translations).order("stories.impressions_count desc, story_translations.published_at desc, story_translations.title asc").uniq
  end
  def self.likes
    joins(:story_translations).order("stories.cached_votes_total desc, story_translations.published_at desc, story_translations.title asc").uniq
  end
  def self.comments
    joins(:story_translations).order("stories.comments_count desc, story_translations.published_at desc, story_translations.title asc").uniq
  end

  #################################
  # settings to clone story
	amoeba do
    enable

    # reset some fields
    nullify :reviewer_key
    nullify :staff_pick
    # nullify :impressions_count
    # nullify :cached_votes_total
    # nullify :cached_votes_score
    # nullify :cached_votes_up
    # nullify :cached_votes_down
    # nullify :cached_weighted_score
    # nullify :comments_count

    # reset counters to 0
    # for some reason nullify is not working for these
    customize(lambda { |original_asset,new_asset|
      new_asset.impressions_count = 0
      new_asset.comments_count = 0
      new_asset.cached_votes_total = 0
      new_asset.cached_votes_score = 0
      new_asset.cached_votes_up = 0
      new_asset.cached_votes_down = 0
      new_asset.cached_weighted_score = 0
    })

    # do not copy impression views
    exclude_field :impressions

    # do not copy votes
    exclude_field :votes_for

    # tags cannot be cloned - think this is because the story_id is saved under taggable_id
    exclude_field :tag_taggings

    # do not copy invitation
    exclude_field :invitations

    # clone the associations
		clone [:story_translations, :sections, :categories, :themes]
	end

  #################################

  # override find by permalink method so that it does not require the current I18n.locale
  def self.find_by_permalink(permalink)
    joins(:story_translations).where(:story_translations => {:permalink => permalink}).first
  end

  def self.can_edit?(story_id, user_id)
    x = select('id').where(:id => story_id).editable_user(user_id)  
    return x.present?
  end

  def self.editable_user(user_id)
    where("stories.user_id = :id or stories.id in ( select story_id from stories_users t where t.user_id = :id )",
      :id => user_id)
  end

  # get entire story with the id and locale
	def self.fullsection(story_id, locale=nil)
    s = Story.select('stories.id, stories.story_locale').find_by_id(story_id)

    if s.present?
      locale ||= s.story_locale
      # x = includes({sections: [:media,:content,:embed_medium,:youtube,:slideshow]})
      #   .where(stories: {id: story_id})
      #   .first

      x = includes(:translations, {sections: [:media,:content,:embed_medium,:youtube,:slideshow]})
        .where(stories: {id: story_id})
        .with_locales(locale)
        .first

      # x = includes({sections: [:media,:content,:embed_medium,:youtube,:slideshow]})
      #   .where(stories: {id: story_id})
      #   .with_translations(locale)
      #   .first

      # x.translation_for(locale)

      return x
    end
	end
	
	def self.demo
	  fullsection(DEMO_ID)
	end
	
	def self.by_language(locale)
	  where(:story_locale => locale)
	end

	def self.by_category(id)
	  joins(:categories).where('categories.id = ?', id)
	end
	
	def self.by_authors(user_ids)
    where(:user_id => user_ids)
	end
	
	# get all of the unique story locales for published stories
	def self.published_locales
	  joins(:story_translations).select('story_translations.locale').is_published.map{|x| x.locale}.uniq.sort
	end

	# get all of the unique story cateogires for published stories
	def self.published_categories
    joins(:story_categories).select('story_categories.category_id').is_published.map{|x| x['category_id']}.uniq.sort
	end

  def self.include_categories
    includes(:categories)
  end

  # get list of users that match the passed in query
  # - user must not be owner or already have invitation or is already collaborator
  # - search in user nickname and email
  def user_collaboration_search(q, limit=10)
    if q.present? and q.length > 1
      already_exists_ids = []
      already_exists_emails = []
      # add owner
      already_exists_ids << self.user_id
      # add colaborators
      if self.users.present?
        already_exists_ids << self.users.map{|x| x.id}
      end
      # add invitations
      pending = Invitation.pending_by_story(self.id)
      if pending.present?
        already_exists_emails << pending.map{|x| x.to_email}
      end
      
      already_exists_ids.flatten!
      already_exists_emails.flatten!
      
      sql = ""
      if already_exists_ids.present? && already_exists_emails.present?
        sql = "!(id in (:ids) or email in (:emails)) and "
      elsif already_exists_ids.present?
        sql = "!(id in (:ids)) and "
      elsif already_exists_emails.present?
        sql = "!(email in (:emails)) and "
      end
      sql << "(nickname like :search or email_no_domain like :search)"
      users = User.where([sql, 
          :ids => already_exists_ids.uniq,
          :emails => already_exists_emails.uniq,
          :search => "%#{q}%"])
          .limit(limit)          
      return users
    end  
  end


  # alias name for cached_votes_total
  def likes
    self.cached_votes_total
  end


	def asset_exists?
		self.asset.present? && self.asset.asset.exists?
	end  		

	def transliterate_file_name
	  if thumbnail_file_name.present?
	    extension = File.extname(thumbnail_file_name).gsub(/^\.+/, '')
	    filename = thumbnail_file_name.gsub(/\.#{extension}$/, '')
	    self.thumbnail.instance_write(:file_name, "#{StoriesHelper.transliterate(filename)}.#{StoriesHelper.transliterate(extension)}")
	  end
	end
	
  # use amoeba to clone the story and all of its records
  # after the clone is complete, copy all assets from the original story to the new story
  def clone_story
    clone = self.amoeba_dup
    if clone.save
      puts "$$$$$$$$$ clone successful - copying asset files"

      # copy the assets
      # - have to copy each one by hand so can update the file name with the id of the new asset
      original_id = self.id
      new_id = clone.id

      # story thumbnail
      puts "$$$$$$$$$ clone successful - copying thumbnail"
      if self.asset.present? && self.asset.asset.exists? 
        Dir.glob(self.asset.asset.path.gsub('/original/', '/*/')).each do |file|       
          copy_asset file, file.gsub("/thumbnail/#{original_id}/", "/thumbnail/#{new_id}/") 
        end
      end

      # section audio
      puts "$$$$$$$$$ clone successful - copying audio"
      new_audio = clone.sections.select{|x| x.asset.present? && x.asset.asset.exists?}.map{|x| x.asset}
      self.sections.select{|x| x.asset.present? && x.asset.asset.exists?}.map{|x| x.asset}.each do |audio|
        # find matching record
        record = new_audio.select{|x| x.asset_file_name == audio.asset_file_name && 
                                      x.asset_content_type == audio.asset_content_type && 
                                      x.asset_file_size == audio.asset_file_size && 
                                      x.asset_updated_at == audio.asset_updated_at}.first
        # copy the file if match found
        if record.present?
          copy_asset audio.asset.path, audio.asset.path.gsub("/audio/#{original_id}/", "/audio/#{new_id}/")
                                                        .gsub("/#{audio.id}__", "/#{record.id}__") 
        end
      end

      # slideshow
      puts "$$$$$$$$$ clone successful - copying slideshow"
      new_ss = clone.sections.select{|x| x.slideshow?}.map{|x| x.slideshow.assets}.flatten.select{|x| x.asset.exists?}
      self.sections.select{|x| x.slideshow?}.map{|x| x.slideshow.assets}.flatten.select{|x| x.asset.exists?}.each do |img|
        # find matching record
        record = new_ss.select{|x| x.asset_file_name == img.asset_file_name && 
                                      x.asset_content_type == img.asset_content_type && 
                                      x.asset_file_size == img.asset_file_size && 
                                      x.asset_updated_at == img.asset_updated_at}.first
        # copy the file if match found
        if record.present?
          Dir.glob(img.asset.path.gsub('/original/', '/*/')).each do |file|       
            copy_asset file, file.gsub("/slideshow/#{original_id}/", "/slideshow/#{new_id}/") 
                                  .gsub("/#{img.id}__", "/#{record.id}__") 
          end
        end
      end


      # images
      puts "$$$$$$$$$ clone successful - copying images"
      new_img = clone.sections.select{|x| x.media?}.map{|x| x.media}.flatten.select{|x| x.image_exists?}.map{|x| x.image}
      self.sections.select{|x| x.media?}.map{|x| x.media}.flatten.select{|x| x.image_exists?}.map{|x| x.image}.each do |img|
        # find matching record
        record = new_img.select{|x| x.asset_file_name == img.asset_file_name && 
                                      x.asset_content_type == img.asset_content_type && 
                                      x.asset_file_size == img.asset_file_size && 
                                      x.asset_updated_at == img.asset_updated_at}.first
        # copy the file if match found
        if record.present?
          Dir.glob(img.asset.path.gsub('/original/', '/*/')).each do |file|       
            copy_asset file, file.gsub("/images/#{original_id}/", "/images/#{new_id}/") 
                                  .gsub("/#{img.id}__", "/#{record.id}__") 
          end
        end
      end

      # videos
      puts "$$$$$$$$$ clone successful - copying videos"
      new_video = clone.sections.select{|x| x.media?}.map{|x| x.media}.flatten.select{|x| x.video_exists?}.map{|x| x.video}
      self.sections.select{|x| x.media?}.map{|x| x.media}.flatten.select{|x| x.video_exists?}.map{|x| x.video}.each do |video|
        # find matching record
        record = new_video.select{|x| x.asset_file_name == video.asset_file_name && 
                                      x.asset_content_type == video.asset_content_type && 
                                      x.asset_file_size == video.asset_file_size && 
                                      x.asset_updated_at == video.asset_updated_at}.first
        # copy the file if match found
        if record.present?
          # it is possible that the original video is not mp4 so need to look for anything that has same basename (ignore file ext)
          ext = File.extname(video.asset.path)
          basename = File.basename(video.asset.path)
          name = File.basename(video.asset.path, ext)

          Dir.glob(video.asset.path.gsub('/original/', '/*/').gsub(basename, "#{name}.*")).each do |file|       
            copy_asset file, file.gsub("/video/#{original_id}/", "/video/#{new_id}/") 
                                  .gsub("/#{video.id}__", "/#{record.id}__") 
          end

          # get the poster folder too
          copy_asset video.asset.path(:poster), video.asset.path(:poster).gsub("/video/#{original_id}/", "/video/#{new_id}/") 
                                .gsub("/#{video.id}__", "/#{record.id}__") 

        end
      end

      # # look in each directory in path and see if it has folder for original_id
      # # if so, copy it for new story
      # Dir.glob("#{path}/*").select {|f| File.directory? f}.each do |directory|
      #   if Dir.exists?("#{directory}/#{original_id}")
      #     puts "$$$$$$$$$ - copying files from #{directory}"
      #     FileUtils.cp_r "#{directory}/#{original_id}", "#{directory}/#{new_id}"
      #   end
      # end
    end

    return clone
  end


  def show_asset
    if self.asset.nil?
      Asset.new(:asset_type => Asset::TYPE[:story_thumbnail])
    else
      self.asset
    end
  end
  
  # when a comment occurs, update the count by 1
  def increment_comment_count
    self.comments_count += 1
    self.save
  end
  
  # remove quotes from tags
  def tag_list_tokens=(tokens)
    self.tag_list = tokens.gsub("'", "")
  end  
  
  

  private 

  def copy_asset(original_path, new_path)
    # make sure new path directory structure exists
    FileUtils.mkdir_p(File.dirname(new_path))
    FileUtils.cp original_path, new_path
  end  
end
