require 'menu/builder'

module Menu
  class Base < Tags::Tag
    class_inheritable_accessor :definitions
    self.definitions = []

    class << self
      def define(*args, &block)
        definitions << [block, args.extract_options!]
      end
    end

    attr_accessor :id, :url, :active, :parent, :children
    attr_writer :activates, :breadcrumbs

    def initialize(id = nil, options = {})
      super(options)
      @id = id || self.class.name.demodulize.underscore.sub('_menu', '').to_sym
      @breadcrumbs = []
		  [:text, :content, :url].each { |key| instance_variable_set(:"@#{key}", options.delete(key)) }
    end

    def find(key)
      child = children.detect { |item| item.id == key } and return child
      children.each { |child| child = child.find(key) and return child }
      nil
    end

    def [](*keys)
      return self if keys.empty?
      keys = keys.first.to_s.split('.').map(&:to_sym) + keys[1, keys.size] if keys.first
      key = keys.shift
      child = children.detect { |item| item.id == key } or raise "can not find item #{key.inspect}"
      (child.nil? || keys.empty?) ? child : child[*keys]
    end

    def activates
      @activates ||= parent
    end

    def breadcrumbs
      (activates ? activates.breadcrumbs : []) + @breadcrumbs
    end

    def activation_path
      [self] + Array(activates ? activates.activation_path : nil).compact
    end

    def activate(path)
      path == url ? activation_path.each { |item| item.active = self } : self.active = false
      children.each { |child| child.activate(path) }
    end

    def render(options = {})
      super(options) { |html| children.each { |child| html << child.render } }
    end

    def reset
      self.active = false
      children.each(&:reset)
    end

    def build(scope = nil)
      @built = true
      Builder.new(self, scope, definitions)
      populate(scope)
      activate(scope.request.path) if scope
      self
    end

    def populate(scope)
      children.each { |child| child.populate(scope) if child.respond_to?(:populate) }
    end

    def build?
      !@built && !definitions.empty?
    end
  end

  class Item < Base
    def breadcrumbs
      breadcrumbs = Array(activates.breadcrumbs).compact
      breadcrumbs << self.dup unless breadcrumbs.map(&:id).include?(id)
      breadcrumbs
    end

    def render
	    tag = Tags::Li.new(content, :class => 'item')
	    tag.add_class('active') if active
	    tag.render
    end

    def text
      @text ||= id.is_a?(Symbol) ? I18n.t(id, :scope => :'adva.titles') : id
    end

	  def content
	    @content ||= url ? Tags::A.new(text, :href => url).render : Tags::Span.new(text).render
    end
  end

  class Menu < Base
    self.tag_name = 'ul'
  end

  class Group < Base
    self.tag_name = 'div'
  end

	class SectionsMenu < Item
	  attr_reader :sections

	  def initialize(*args)
	    super
	    @sections = []
    end

    def populate(scope)
      scope.instance_eval(&@options[:populate]).each do |s|
	      @sections << Base.new(s.title, :level => s.level, :url => scope.admin_section_contents_path(s))
      end
    end

    def breadcrumbs
      Array(activates.breadcrumbs).compact + [item, active_section].compact
    end

    def activate(path)
      super
      path = path =~ %r((^.*/sections/[\d]+)) && $1 or return
      @sections.each { |section| section.active = self if section.url.starts_with(path) }
    end
    
    def item
      Item.new id, :text => @text, :content => @content, :url => @url
    end
    
    def active_section
      section = sections.detect { |section| section.active } 
      section && Item.new(:section, :text => section.id, :url => @url)
    end

    def content
      super + Tags::Ul.new(:id => 'sections_menu').render do |html|
        sections.each do |section|
          section.add_class("level_#{[section.level, 10].min}" + (section.active ? ' active' : ''))
          link = Tags::A.new(section.id, :href => section.url, :class => section.options[:class])
          html << Tags::Li.new(link.render).render
        end
      end
    end
  end
end
