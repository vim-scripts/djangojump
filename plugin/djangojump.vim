" *********************************
" vim-djangojump plugin is used for 
" jumping between view function and
" template immediately.
"
" note: now open vim at django project's
" root path where has settings.py file
"
" author: zack
"
" tip:
" 1. url => view function
"    :DUrltoview /xxx/yyy/
"
" 2. view function ==> template file
"    :DViewtotpl (at line which contains
"    template's name)
"
"    example code:
"       ....
"    (*)   return render_to_response("index.html")
"
"    cursor at this line(*) and call command 
"    :DViewtotpl
"
" 3. template file ==> view function
"    :DTpltoview
"
" 4. js which template includes ==> js source file
"    css which template includes ==> css source file
"    :DGotoscript
"
" 5. reload cache
"    :DReloadCache
"
" 6. url => template file
"    :DUrltotpl /xxx/yyy/
"
" *********************************


python << EOF

import vim
import os
import imp
import sys
import re

PROJECT = os.path.basename(os.path.abspath(os.curdir))
PROJECT_PATH = os.path.abspath(os.curdir)
CONFIG_PATH = os.path.expanduser('~/.djangojump/')
SETTINGS = "settings"

DJANGO_SETTINGS_MODULE = "%s.%s" %(PROJECT, SETTINGS)

sys.path.append(os.path.abspath('.'))
sys.path.append(os.path.join(os.path.abspath('.'), '..'))

template_cache_dir_map = {}
template_view_map_cache = {}
view_template_map_cache = {}
pattern_cache = []

try:
    imp.find_module(SETTINGS)
except Exception, e:
    pass
else:
    os.environ['DJANGO_SETTINGS_MODULE'] = DJANGO_SETTINGS_MODULE
    import settings

def load_tplname_to_cache():
    
    import cPickle

    if not os.path.exists(CONFIG_PATH):
        os.mkdir(CONFIG_PATH) 

    global template_view_map_cache
    global view_template_map_cache
    global pattern_cache
    cache_file = os.path.join(CONFIG_PATH, 'template_view_map_cache')
    cache_file_view_template = os.path.join(CONFIG_PATH, 'view_template_map_cache')
    pattern_cache_file = os.path.join(CONFIG_PATH, 'pattern_cache')
    if os.path.exists(cache_file):
        try:
            template_view_map_cache = cPickle.load(open(cache_file, 'r'))
            view_template_map_cache = cPickle.load(open(cache_file_view_template, 'r'))
        except Exception,e:
            print e

        try:
            pattern_cache = cPickle.load(open(pattern_cache_file, 'r'))
        except Exception,e:
            print e

        return

    from django.core.urlresolvers import RegexURLPattern, RegexURLResolver

    try:
        import settings
    except:
        return

    imp_m = __import__(settings.ROOT_URLCONF)
    try:
        urlpatterns = imp_m.urls.urlpatterns
    except:
        urlpatterns = imp_m.urlpatterns

    template_dirs = None
    try:
        template_dirs = settings.TEMPLATE_DIRS
    except:
        return


    def load_tpl_view_to_cache(urlpatterns, prefix_pattern=None):
        for url in urlpatterns:
            if isinstance(url, RegexURLResolver):
                load_tpl_view_to_cache(url.url_patterns, url._regex)
            elif isinstance(url, RegexURLPattern):
                _callback = None
                try:
                    _callback = '%s.%s' %(url._callback.__module__, url._callback.__name__)
                except:
                    _callback = url._callback_str

                if _callback.find('django') == 0:
                    continue
                else:
                    # rebuild pattern
                    url_regexp = ''
                    if prefix_pattern:
                        url_regexp = url._regex
                        if url_regexp.find('^') == 0:
                            url_regexp = url_regexp[1:]
                            url_regexp = '%s%s' %(prefix_pattern, url_regexp)
                        else:
                            url_regexp = '%s%s' %(prefix_pattern, url_regexp)
                    else:
                        url_regexp = url._regex

                    _callback_split = _callback.split('.')
                    sep = os.path.sep
                    module_path_part = sep.join(_callback_split[:len(_callback_split)-1]) + ".py"
                    module_abs_path = os.path.join(PROJECT_PATH, module_path_part)
                    method_name = _callback_split[-1]

                    pattern_cache.append({'module': module_abs_path, 'method': method_name, 'regexp': url_regexp})

                    with open(module_abs_path, 'r') as fp:
                        code_block = []
                        isAfterFunc = False
                        view_at_line_num = 0
                        for line in fp:
                            view_at_line_num += 1
                            match = re.search('^def\s+%s' %method_name, line)
                            if match:
                                code_block.append(line)
                                isAfterFunc = True
                                continue
                            
                            if isAfterFunc:
                                code_block.append(line)
                                match2 = re.search('^def\s+.+', line)
                                if match2:
                                    break
                        
                        for cline in code_block:
                            match = re.search('[\'\"].+\.html[\'\"]', cline)
                            if match:
                                tpl_part_path = match.group()
                                tpl_part_path = tpl_part_path[1:len(tpl_part_path)-1]
                                for tmpdir in template_dirs:
                                    tpl_abspath = os.path.join(tmpdir, tpl_part_path)
                                    if os.path.exists(tpl_abspath):
                                        view_at_line_num -= len(code_block)
                                        template_view_map_cache.setdefault(tpl_abspath, []).append({'path': module_abs_path, 'linenum': view_at_line_num})
                                        view_template_map_cache.setdefault('%s#%s' %(module_abs_path, method_name), []).append(tpl_abspath)
    
    load_tpl_view_to_cache(urlpatterns)

    try:
        cPickle.dump(template_view_map_cache, open(cache_file, 'w'))
        cPickle.dump(view_template_map_cache, open(cache_file_view_template, 'w'))
        cPickle.dump(pattern_cache, open(pattern_cache_file, 'w'))
    except Exception, e:
        pass

load_tplname_to_cache()

    
def url_to_view(url):
    for pattern in pattern_cache:
        regexp = pattern.get('regexp', None)
        if regexp:
            if url.find('/') == 0:
                url = url[1:]
            if not url.endswith('/'):
                url += '/'
            match = re.match(regexp, url)
            if match:
                module_abs_path = pattern.get('module')
                method_name = pattern.get('method')
                vim.command(":set wrapscan")
                vim.command(":e %s" %module_abs_path)
                vim.command("/^def\_s%s(" %method_name)
                break
                
def url_to_template(url):
    for pattern in pattern_cache:
        regexp = pattern.get('regexp', None)
        if regexp:
            if url.find('/') == 0:
                url = url[1:]
            if not url.endswith('/'):
                url += '/'
            match = re.match(regexp, url)
            if match:
                module_abs_path = pattern.get('module')
                method_name = pattern.get('method')

                key = '%s#%s' %(module_abs_path, method_name)
                for tplpath in view_template_map_cache.get(key, []):
                    # TODO more, need a window to show all tplpath
                    vim.command(":e %s" %tplpath)
                    return


def view_to_template():
    template_dirs = None
    try:
        template_dirs = settings.TEMPLATE_DIRS
    except:
        return
    
    line = vim.current.line
    line = "".join(line)

    match = re.search('[\'\"].+\.html[\'\"]', line)
    if match:
        html_name = match.group()
        html_name = html_name[1:len(html_name)-1]
        html_name_split = html_name.split('/')
        html_name = html_name_split[len(html_name_split) - 1]
        left_path = "/".join(html_name_split[0:len(html_name_split)-1])

        def get_abspath_from_cache(tpl_name, path_left_part=None):
            part_path = os.path.join(path_left_part, tpl_name)
            for abspath in template_cache_dir_map.get(tpl_name, []):
                if abspath.find(part_path) > 0:
                    return abspath
    
        def get_tpl_abspath(tpl_name, path_left_part):
            tmp_dir = get_abspath_from_cache(tpl_name, path_left_part)
            if tmp_dir:
                return tmp_dir

            for tpldir in template_dirs:
                for dirpath, dirnames, filenames in os.walk(tpldir):
                    for fname in filenames:
                        if fname == tpl_name:
                            abspath = os.path.abspath(os.path.join(dirpath, fname))
                            part_path = os.path.join(path_left_part, tpl_name)
                            if abspath.find(part_path) > 0:
                                return abspath

        tpl_abspath = get_tpl_abspath(html_name, left_path)

        def is_in_dir_cache(tpl_path):
            tpl_key = os.path.basename(tpl_path)
            for path in template_cache_dir_map.get(tpl_key, []):
                if path == tpl_path:
                    return True

        def add_to_tpl_cache(tpl_abspath):
            if not is_in_dir_cache(tpl_abspath):
                tpl_key = os.path.basename(tpl_abspath)
                template_cache_dir_map.setdefault(tpl_key, []).append(tpl_abspath)

        if tpl_abspath:
            add_to_tpl_cache(tpl_abspath)
            vim.command(":e %s" % tpl_abspath)

def template_to_view():
    tpl_abspath = vim.current.window.buffer.name
    view_paths = template_view_map_cache.get(tpl_abspath, None)
    if view_paths:
        vp = view_paths[0]
        path = vp.get('path')
        linenum = vp.get('linenum')
        if os.path.exists(path):
            vim.command(':e %s' %path)
            vim.command(':%d' %linenum)

def reload_to_cache():
    print 'start reload'
    cache_file = os.path.join(CONFIG_PATH, 'template_view_map_cache')
    pattern_cache_file = os.path.join(CONFIG_PATH, 'pattern_cache')
    try:
        os.remove(cache_file)
        os.remove(pattern_cache_file)
    except Exception,e:
        print e
    load_tplname_to_cache()
    print 'finish reload'

def go_to_js_css():
    line = vim.current.line
    line = "".join(line)

    match_css = re.search('<link.*rel="stylesheet".*>', line)
    if match_css:
        find_css()

    match_js = re.search('<script.*type="text/javascript".*></script>', line)
    if match_js:
        find_js()

def find_css():
    line = vim.current.line
    line = "".join(line)
    
    static_dir = None
    try:
        static_dir = settings.STATIC_ROOT
    except:
        return

    match_css = re.search('<link.*rel="stylesheet".*>', line)
    if match_css:
        match = re.search('href=[\'\"].*\.css[\'\"]', line)
        if match:
            css = match.group()
            css = css[6:len(css)-1]
            css = css.split('/')[-1]

            for dirpath, dirnames, filenames in os.walk(static_dir):
                for fname in filenames:
                    if fname == css:
                        css_abspath = os.path.join(dirpath, fname)
                        vim.command(":e %s" %css_abspath)
                        return


def find_js():
    line = vim.current.line
    line = "".join(line)
    
    static_dir = None
    try:
        static_dir = settings.STATIC_ROOT
    except:
        return
    
    match_js = re.search('<script.*type="text/javascript".*></script>', line)
    if match_js:
        match = re.search('src=[\'\"].*\.js[\'\"]', line)
        if match:
            js = match.group()
            js = js[5:len(js)-1]
            js = js.split('/')[-1]

            for dirpath, dirnames, filenames in os.walk(static_dir):
                for fname in filenames:
                    if fname == js:
                        js_abspath = os.path.join(dirpath, fname)
                        vim.command(":e %s" %js_abspath)
                        return


EOF

com! -nargs=1 DUrltoview python url_to_view(<f-args>)
com! -nargs=1 DUrltotpl python url_to_template(<f-args>)
com! DViewtotpl python view_to_template()
com! DTpltoview python template_to_view()
com! DReloadCache python reload_to_cache()
com! Dfindcss python find_css()
com! Dfindjs python find_js()
com! DGotoscript python go_to_js_css()

nmap <c-d><c-t> :DTpltoview<CR>
nmap <c-d><c-v> :DViewtotpl<CR>
nmap <c-d><c-u> :DUrltoview 
nmap <c-d><c-i> :DUrltotpl 
nmap <c-d><c-s> :DGotoscript<CR>
nmap <c-d><c-r> :DReloadCache<CR>
