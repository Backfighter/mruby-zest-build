class DrawSeqNode
    attr_reader :x, :y, :w, :h, :item, :layer
    def initialize(x,y,item)
        @x     = x.to_i
        @y     = y.to_i
        @w     = item.w.to_i
        @h     = item.h.to_i
        @item  = item
        @layer = item.layer
    end

    def hit?(x,y)
        hx = @x <= x && x <= @x+@w
        hy = @y <= y && y <= @y+@h
        hx && hy
    end

    def intersect?(dmg)
        (rect, layer) = dmg
        if(layer == @layer)
            left_in  = rect.x       >=@x && rect.x       <=@x+@w
            right_in = rect.x+rect.w>=@x && rect.x+rect.w<=@x+@w
            lr_in    = rect.x       <=@x && rect.x+rect.w>=@x+@w

            top_in   = rect.y       >=@y && rect.y       <=@y+@h
            bot_in   = rect.y+rect.h>=@y && rect.y+rect.h<=@y+@h
            tb_in    = rect.y       <=@y && rect.y+rect.h>=@y+@h

            (left_in || right_in || lr_in) && (top_in || bot_in || tb_in)
        else
            false
        end
    end

    def to_s
        "<DrawSeqNode x:#{@x} y:#{@y} w:#{@w} h:#{@h} layer:#{@layer}>"
    end
    def inspect
        to_s
    end
end

class DrawSequence
    attr_accessor :window, :damage, :seq
    def initialize
        @damage        = []
        @damage_layers = []
        @seq           = []
    end

    # Force a redraw in the given region
    def damage_region(region, layer)
        if(@damage != :everything)
            @damage << [region, layer]
        end
        @damage_layers << layer
        @window.refresh
    end

    # Add a widget to the draw sequence
    def add(item, xoff, yoff)
        if(item.respond_to? :draw)
            @seq << DrawSeqNode.new(xoff, yoff, item)
        end
    end

    def make_draw_sequence_recur(item, xoff, yoff)
        xoff = xoff.to_i
        yoff = yoff.to_i
        if(item && xoff && yoff)
            add(item, xoff, yoff)
            item.children.each do |ch|
                if(ch.y && ch.x)
                    make_draw_sequence_recur(ch, xoff+ch.x, yoff+ch.y)
                else
                    puts "bad x/y"
                    puts "widget = <#{ch}>"
                end
            end
        end
    end

    def make_draw_sequence(root)
        @seq = []
        make_draw_sequence_recur(root, 0, 0)
    end

    #Run the full draw sequence
    def render(vg, w, h, fbo)
        (background_fbo, animation_fbo, overlay_fbo, redraw_fbo) = fbo
        drawn_widgets = 0
        if(false)
            puts background_fbo
            puts animation_fbo
            puts overlay_fbo
            puts redraw_fbo
        end
        #[@background_fbo, @animation_fbo, @overlay_fbo, @redraw_fbo].each do |fbo|
        #    fbo.select
        #    GL::gl_viewport(0, 0, w, h);
        #    GL::gl_clear_color(0, 0, 0, 1.0);
        #    GL::gl_clear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
        #end
        (0..2).each do |layer_id|
            updating_layer = @damage_layers.include?(layer_id)
            next if !updating_layer

            selected_fbo = nil
            if(layer_id == 0)
                selected_fbo = background_fbo
            elsif(layer_id == 1)
                selected_fbo = animation_fbo
            elsif(layer_id == 2)
                selected_fbo = overlay_fbo
            end

            redraw_fbo.select
            #puts "running draw sequence on #{w}x#{h} window"
            GL::gl_viewport(0, 0, w, h);
            GL::gl_clear_color(0, 0, 0, 0.0);
            GL::gl_clear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);

            GL::gl_viewport(0, 0, w, h);
            vg.draw(w,h,1.0) do |v|
                @seq.each do |n|
                    if(n.layer == layer_id)
                        #Check if damage overlaps with widget
                        is_clean = true
                        @damage.each do |dmg|
                            is_clean = false if n.intersect?(dmg)
                        end
                        next if is_clean

                        drawn_widgets += 1
                        v.spork do |vv|
                            vv.translate(n.x,n.y)
                            n.item.draw(vv)
                        end
                    end
                end
            end
            selected_fbo.select

            #puts @damage
            @damage.each do |dmg|
                next if(dmg[1] != layer_id)
                d = dmg[0]
                GL::gl_viewport(0,0,w,h)
                GL::gl_scissor(d.x, h-(d.y+d.h), d.w, d.h)
                GL::gl_clear_color(0, 0, 0, 0.0)
                GL::gl_clear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
                GL::gl_scissor_end
            end


            redraw_img = get_image(redraw_fbo)
            #@damage = [[Rect.new(0, 0, 512,512)]]

            GL::gl_viewport(0, 0, w, h);
            vg.draw(w, h, 1.0) do |v|
                @damage.each do |dmg|
                    next if(dmg[1] != layer_id)
                    d = dmg[0]
                    pat = vg.image_pattern(0,h,w,h,0,redraw_img.image, 1.0)
                    vg.path do |p|
                        p.rect(d.x-0.5,d.y+0.5,d.w,d.h)
                        v.fill_paint pat
                        v.fill
                    end
                end
            end
        end

        # Composite the layers
        layers = []
        layers << get_image(background_fbo)
        layers << get_image(animation_fbo)
        layers << get_image(overlay_fbo)
        redraw_fbo.deselect

        GL::gl_viewport(0, 0, w, h);
        GL::gl_clear_color(0, 0, 0, 1.0)
        GL::gl_clear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);

        vg.draw(w, h, 1.0) do |v|
            layers.each do |img|
                pat = vg.image_pattern(0,h,w,h,0,img.image, 1.0)
                vg.path do |p|
                    p.rect(0, 0, w, h)
                    v.fill_paint pat
                    v.fill
                end
            end
        end

        print drawn_widgets
        @damage_layers = []
        @damage        = []
    end

    def get_image(fbo)
        im = fbo.image $vg
        Nanovg::ImageHandle.new($vg, im)
    end


    #Find a widget which should accept a particular event
    # - Widgets which are drawn later take higher precedence
    # - Widgets drawn on the animation layer cannot receive events
    # - Widgets drawn on the overlay layer take precedence over the ground layer
    #
    # inputs:
    # - x location relative to the root of the window
    # - y location relative to the root of the window
    # - optional method which widget must respond to
    #  (filters out decoration widgets)
    def event_widget(x, y, method=nil)
        selected_item  = nil
        selected_layer = 0
        @seq.each do |elm|
            next if elm.layer == 1
            next if selected_layer == 2 && elm.layer != 2
            if(elm.hit?(x,y))
                selected_item  = elm.item
                selected_layer = elm.layer
            end
        end
        selected_item
    end

    private :make_draw_sequence_recur

end
