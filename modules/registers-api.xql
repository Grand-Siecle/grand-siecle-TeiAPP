xquery version "3.1";

module namespace rview="http://teipublisher.com/api/registers/view";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config" at "pm-config.xql";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "util.xql";
import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace page="http://teipublisher.com/ns/templates/page" at "templates/page.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare function rview:sort($people as array(*)*, $dir as xs:string) {
    let $sorted :=
        sort($people, "?lang=de-DE", function($entry) {
            $entry?1
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)
};

declare function rview:people-all($request as map(*)) {
    let $people := collection($config:register-root)/id($config:register-map?person?id)//tei:person[ft:query(., '*', map {
        "leading-wildcard": "yes",
        "filter-rewrite": "yes"
    })]
    let $byKey := for-each($people, function($person as element()) {
        let $label := ft:field($person, "sort-name")
        return
            [lower-case($label), $person]
    })
    let $sorted := rview:sort($byKey, "asc")
    return array { 
        for $person in $sorted
        where $person?1
        return
            map {
                "id": $person?2/@xml:id/string(),
                "name": $person?2/tei:persName[@type="main"]/string(),
                "sort-name": $person?1
            }
     }
};

declare function rview:people-categories($request as map(*)){
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $sortDir := ($request?parameters?dir, 'asc')[1]
    let $limit := head(($request?parameters?limit, -1))
    let $show-notes := $request?parameters?description = 'on'
    let $odd := head(($request?parameters?odd, $config:default-odd))
    let $people :=
            if ($search and $search != '') then
                collection($config:register-root)/id($config:register-map?person?id)//tei:person[ft:query(., 'name:(' || $search || '*)')]
            else
                collection($config:register-root)/id($config:register-map?person?id)//tei:person[ft:query(., '*', map {
                        "leading-wildcard": "yes",
                        "filter-rewrite": "yes"
                    })]
    let $byKey := for-each($people, function($person as element()) {
        let $label := ft:field($person, "sort-name")
        return
            [lower-case($label), $label, $person]
    })
    let $sorted := rview:sort($byKey, $sortDir)
    let $letter := 
        if ($limit < 0 or count($people) < $limit) then 
            "all"
        else if ($letterParam = '') then
            substring($sorted[1]?1, 1, 1) => upper-case()
        else
            $letterParam
    let $byLetter :=
        if ($letter = 'all') then
            $sorted
        else
            filter($sorted, function($entry) {
                starts-with($entry?1, lower-case($letter))
            })
    return
        map {
            "items": rview:output-person-all($byLetter, $letter, $search, $odd, $show-notes),
            "categories":
                if (count($people) < $limit) then
                    []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count(filter($sorted, function($entry) { starts-with($entry?1, lower-case($alpha))}))
                    where $hits > 0
                    return
                        map {
                            "category": $alpha,
                            "count": $hits
                        },
                    map {
                        "category": "all",
                        "count": count($sorted)
                    }
                }
        }
};

declare function rview:output-person-all($list as array(*)*, $letter as xs:string,  $search as xs:string?, $odd as xs:string, $show-notes as xs:boolean) {
    array {
        for $person in $list
        let $letterParam := if ($letter = "all") then substring($person?3/@n, 1, 1) else $letter
        let $note := 
            $pm-config:web-transform($person?3, map { "mode": "register-overview", "show-notes": $show-notes }, $odd)
        return
            <div class="split-list-item">
            { $note }
            </div>
    }
};

declare function rview:detail-html($request as map(*)) {
    let $id := xmldb:decode-uri($request?parameters?id)
    let $entry := collection($config:register-root)/id($id) => head()
    let $config := tpu:parse-pi(root($entry), $request?parameters?view, $request?parameters?odd)
    let $type := rview:entry-type($entry)
    let $extConfig := map {
        "entity-data": map {
            "id": $id,
            "root": $entry,
            "type": $type,
            "slug": rview:slug($type),
            "label": rview:entry-label($entry),
            "body": rview:detail-body($entry, $type),
            "backlinks": rview:backlinks($entry),
            "transform": page:transform(?, ?, $config?odd),
            "transform-with": page:transform#3
        }
    }
    return
        vapi:html($request, $extConfig)
};

(:~
 : Build the "cited in" backlink block for an authority entry.
 :
 : The inline corpus mentions were rewritten by the NER pipeline to point at the
 : registry ids (@ref="#person-NNNNNN"), and every entry already carries a
 : precomputed reverse index: note[@type='sources'] (pipe-separated corpus
 : document ids) plus @n (total mentions). We use that index-free Tier-1 source
 : to list the citing documents without scanning the (multi-GB) corpus body.
 :
 : Each source token T maps to the corpus file "T_reconciled.tei.xml".
 : Returns () when the entry has no recorded sources (no block is rendered).
 :)
declare function rview:backlinks($entry as element()?) {
    let $id := string($entry/@xml:id)
    let $sources :=
        for $s in tokenize($entry/tei:note[@type = 'sources'], '\|')
        let $t := normalize-space($s)
        where $t != ''
        return $t
    let $total := ($entry/@n[. castable as xs:integer])[1]
    return
        if (empty($sources)) then
            ()
        else
            <div class="gs-backlinks">
                <h2 class="gs-backlinks-title">
                    <pb-i18n key="register.cited-in">Cité dans</pb-i18n>{' '}
                    <span class="gs-backlinks-count">{count($sources)}</span>{' '}
                    <pb-i18n key="register.documents">documents</pb-i18n>
                    {
                        if ($total) then
                            (<span class="gs-backlinks-sep"> · </span>,
                             <span class="gs-backlinks-mentions">{string($total)}</span>,
                             text { ' ' },
                             <pb-i18n key="register.mentions">mentions</pb-i18n>)
                        else
                            ()
                    }
                </h2>
                <ul class="gs-backlinks-list">
                {
                    for $src in $sources
                    let $file := $src || '_reconciled.tei.xml'
                    let $doc := config:get-document($file)
                    let $title := normalize-space(
                        ($doc//tei:fileDesc/tei:titleStmt/tei:title[@type = 'main'],
                         $doc//tei:fileDesc/tei:titleStmt/tei:title)[1])
                    let $label := if ($title != '') then $title else $src
                    order by lower-case($label)
                    return
                        <li class="gs-backlinks-item">
                            <button type="button" class="gs-kwic-toggle" data-id="{$id}" data-doc="{$src}" aria-expanded="false">
                                <span class="gs-backlinks-doc">{$label}</span>
                                <span class="gs-backlinks-id">{$src}</span>
                            </button>
                            <div class="gs-kwic-panel" hidden="hidden"></div>
                        </li>
                }
                </ul>
            </div>
};

(:~ Lazy KWIC endpoint: for an entity id + a source document, return the
 :  passages (keyword-in-context) where the entity is cited. Loaded on demand
 :  when a document is expanded on the authority page, so the (multi-GB) corpus
 :  is never scanned eagerly. Scoped to the element matching the id's type for
 :  speed (uses the element-name index instead of a full //* attribute scan). :)
declare function rview:cited($request as map(*)) {
    let $id := xmldb:decode($request?parameters?id)
    let $src := $request?parameters?doc
    let $file := $src || '_reconciled.tei.xml'
    let $doc := config:get-document($file)
    let $ref := '#' || $id
    let $hits :=
        switch(substring-before($id, '-'))
            case "person" return $doc//tei:persName[@ref = $ref]
            case "place" return $doc//tei:placeName[@ref = $ref]
            case "org" return $doc//tei:orgName[@ref = $ref]
            case "work" return $doc//tei:title[@ref = $ref]
            case "date" return $doc//tei:date[@ref = $ref]
            default return $doc//*[@ref = $ref]
    let $limit := 12
    let $offset := xs:integer((($request?parameters?offset)[. castable as xs:integer], 0)[1])
    let $docUrl := $config:context-path || '/' || $file
    let $label := rview:entry-label(collection($config:register-root)/id($id) => head())
    let $searchUrl := $config:context-path || '/search.html?query=' || encode-for-uri('"' || $label || '"') || '&amp;doc=' || encode-for-uri($file)
    let $count := count($hits)
    let $page := subsequence($hits, $offset + 1, $limit)
    let $remaining := $count - ($offset + $limit)
    let $more :=
        if ($remaining > 0) then
            <button type="button" class="gs-kwic-more-btn" data-id="{$id}" data-doc="{$src}" data-offset="{$offset + $limit}">
                Voir plus ({$remaining} passage{if ($remaining > 1) then 's' else ''})
            </button>
        else ()
    return
        if ($offset = 0) then
            <div class="gs-kwic">
                <div class="gs-kwic-actions">
                    <a class="gs-kwic-open" href="{$docUrl}" target="_blank" rel="noopener">Ouvrir le document ↗</a>
                    <a class="gs-kwic-search" href="{$searchUrl}" target="_blank" rel="noopener" title="Recherche plein-texte « {$label} » dans ce document (nouvel onglet)">Recherche « {$label} » dans ce document ↗</a>
                </div>
                {
                    if ($count = 0) then
                        <p class="gs-kwic-empty">Aucun passage localisé (mention sur un calque non affiché).</p>
                    else
                        for $m in $page
                        return rview:kwic-line($m, $docUrl)
                }
                {$more}
            </div>
        else
            <div class="gs-kwic-batch">
                {for $m in $page return rview:kwic-line($m, $docUrl)}
                {$more}
            </div>
};

(:~ Build one keyword-in-context line around a mention element. :)
declare function rview:kwic-line($m as element(), $docUrl as xs:string) {
    let $block := ($m/ancestor::*[self::tei:p or self::tei:ab or self::tei:head or self::tei:l or self::tei:item][1], $m/..)[1]
    (: the corpus interleaves original + modernized spellings (tei:orig / tei:reg);
       read only the mention's own layer so the snippet isn't doubled :)
    let $excludeOrig := not(exists($m/ancestor::tei:orig))
    let $full := normalize-space(
        string-join(
            $block//text()[if ($excludeOrig) then not(ancestor::tei:orig) else not(ancestor::tei:reg)],
            ' ')
    )
    let $mention := normalize-space(string($m))
    let $win := 80
    return
        <a class="gs-kwic-line" href="{$docUrl}" target="_blank" rel="noopener">
        {
            if ($mention != '' and contains($full, $mention)) then
                let $before := substring-before($full, $mention)
                let $after := substring-after($full, $mention)
                let $pre := if (string-length($before) > $win) then '… ' || substring($before, string-length($before) - $win + 1) else $before
                let $post := if (string-length($after) > $win) then substring($after, 1, $win) || ' …' else $after
                return ($pre, <mark>{$mention}</mark>, $post)
            else
                if (string-length($full) > 170) then substring($full, 1, 170) || ' …' else $full
        }
        </a>
};

(:~ ============================================================================
 :  Generic entity browser & authority-file renderer (Phase 2)
 :
 :  One code path for all 9 register types. Per-type element/label differences
 :  are resolved by rview:entry-* below; the browse list uses a lightweight
 :  server-side row (rview:overview-row) instead of a full ODD transform per
 :  entry, so it scales to the ~7400-person register without a reindex.
 :  ========================================================================== :)

declare variable $rview:type-info := map {
    "person":       map { "entry": "person",   "slug": "people" },
    "place":        map { "entry": "place",     "slug": "places" },
    "organization": map { "entry": "org",       "slug": "organizations" },
    "work":         map { "entry": "bibl",      "slug": "works" },
    "event":        map { "entry": "event",     "slug": "events" },
    "artwork":      map { "entry": "object",     "slug": "artworks" },
    "material":     map { "entry": "category",  "slug": "materials" },
    "technique":    map { "entry": "category",  "slug": "techniques" },
    "date":         map { "entry": "item",      "slug": "dates" }
};

declare function rview:slug($type as xs:string) as xs:string {
    ($rview:type-info($type)?slug, $type)[1]
};

(:~ Canonical type string for a register entry, derived from its element. :)
declare function rview:entry-type($entry as element()?) as xs:string {
    typeswitch($entry)
        case element(tei:person) return "person"
        case element(tei:place) return "place"
        case element(tei:org) return "organization"
        case element(tei:bibl) return "work"
        case element(tei:event) return "event"
        case element(tei:object) return "artwork"
        case element(tei:category) return
            if ($entry/ancestor::tei:taxonomy/@xml:id = 'techniques') then "technique" else "material"
        case element(tei:item) return "date"
        default return "entity"
};

(:~ Main display label for any register entry. :)
declare function rview:entry-label($entry as element()?) as xs:string {
    normalize-space(
        typeswitch($entry)
            case element(tei:person) return ($entry/tei:persName[@type='main'], $entry/tei:persName)[1]
            case element(tei:place) return ($entry/tei:placeName[@type='main'], $entry/tei:placeName)[1]
            case element(tei:org) return ($entry/tei:orgName[@type='main'], $entry/tei:orgName)[1]
            case element(tei:bibl) return ($entry/tei:title[@type='main'], $entry/tei:title)[1]
            case element(tei:event) return ($entry/tei:label[@type='main'], $entry/tei:label)[1]
            case element(tei:object) return ($entry/tei:objectName[@type='main'], $entry/tei:objectName)[1]
            case element(tei:category) return ($entry/tei:catDesc/tei:term[@type='main'], $entry/tei:catDesc/tei:term, $entry/tei:catDesc)[1]
            case element(tei:item) return ($entry/tei:date[not(@type)], $entry/tei:date)[1]
            default return string($entry/@xml:id)
    )
};

(:~ Sort key for an entry (prefers a 'sort' form for actor names). :)
declare function rview:entry-sort($entry as element()?) as xs:string {
    let $s :=
        typeswitch($entry)
            case element(tei:person) return ($entry/tei:persName[@type='sort'], $entry/tei:persName[@type='main'], $entry/tei:persName)[1]
            case element(tei:place) return ($entry/tei:placeName[@type='sort'], $entry/tei:placeName[@type='main'], $entry/tei:placeName)[1]
            case element(tei:org) return ($entry/tei:orgName[@type='sort'], $entry/tei:orgName[@type='main'], $entry/tei:orgName)[1]
            default return rview:entry-label($entry)
    return lower-case(normalize-space($s))
};

(:~ All entries of a type, scoped to its register file. :)
declare function rview:entries($type as xs:string) as element()* {
    let $root := collection($config:register-root)/id($config:register-map?($type)?id)
    return
        switch($type)
            case "person" return $root//tei:person[starts-with(@xml:id, 'person-')]
            case "place" return $root//tei:place[starts-with(@xml:id, 'place-')]
            case "organization" return $root//tei:org[starts-with(@xml:id, 'org-')]
            case "work" return $root//tei:bibl[starts-with(@xml:id, 'work-')]
            case "event" return $root//tei:event[starts-with(@xml:id, 'event-')]
            case "artwork" return $root//tei:object[starts-with(@xml:id, 'artwork-')]
            case "material" return $root//tei:category[starts-with(@xml:id, 'material-')]
            case "technique" return $root//tei:category[starts-with(@xml:id, 'technique-')]
            case "date" return $root//tei:item[starts-with(@xml:id, 'date-')]
            default return ()
};

declare function rview:disp-year($w as xs:string?) as xs:string {
    if (empty($w) or normalize-space($w) = '') then '' else
    try {
        let $neg := starts-with($w, '-')
        let $b := if ($neg) then substring($w, 2) else $w
        let $y := xs:integer(tokenize($b, '-')[1])
        return if ($neg) then string($y) || ' av. J.-C.' else string($y)
    } catch * { string($w) }
};

declare function rview:confidence($entry as element()?) as xs:string {
    normalize-space($entry/tei:note[@type='reconciliation-confidence'])
};

declare function rview:confidence-badge($conf as xs:string?) {
    let $key := if ($conf and $conf != '') then $conf else 'none'
    let $g := switch($conf)
        case "high" return "◆◆◆"
        case "medium" return "◆◆"
        case "low" return "◆"
        default return "○"
    let $lbl := switch($conf)
        case "high" return "réconciliation fiable"
        case "medium" return "réconciliation moyenne"
        case "low" return "réconciliation incertaine"
        default return "non réconciliée"
    return
        <span class="gs-conf gs-conf-{$key}" title="{$lbl}"><span class="gs-conf-glyph">{$g}</span></span>
};

declare function rview:auth-abbr($t as xs:string) as xs:string {
    switch($t)
        case "wikidata" return "Wikidata"
        case "viaf" return "VIAF"
        case "isni" return "ISNI"
        case "gnd" return "GND"
        case "bnf" return "BnF"
        case "lccn" return "LCCN"
        case "geonames" return "GeoNames"
        case "aat" return "Getty AAT"
        default return upper-case($t)
};

declare function rview:auth-url($type as xs:string, $value as xs:string) as xs:string? {
    let $v := normalize-space($value)
    return
    switch($type)
        case "wikidata" return "https://www.wikidata.org/wiki/" || $v
        case "viaf" return "https://viaf.org/viaf/" || $v
        case "isni" return "https://isni.org/isni/" || $v
        case "gnd" return "https://d-nb.info/gnd/" || $v
        case "bnf" return "https://catalogue.bnf.fr/ark:/12148/cb" || $v
        case "lccn" return "https://id.loc.gov/authorities/names/" || $v
        case "geonames" return "https://www.geonames.org/" || $v
        case "aat" return "http://vocab.getty.edu/aat/" || $v
        default return ()
};

declare function rview:authority-chips($entry as element()?) {
    let $types := distinct-values($entry/tei:idno[normalize-space() != '']/@type/string())
    return
        if (empty($types)) then ()
        else
            <span class="gs-auth-chips">
            {
                for $t in $types
                return <span class="gs-auth-chip gs-auth-{$t}" title="{rview:auth-abbr($t)}">{rview:auth-abbr($t)}</span>
            }
            </span>
};

(:~ Compact metadata bits shown after the label in the browse list (the mention
 :  count is shown separately, as a chip next to the label). :)
declare function rview:overview-meta($entry as element(), $type as xs:string) as xs:string* {
    let $specific :=
        switch($type)
            case "person" return
                let $d := string-join((rview:disp-year($entry/tei:birth/tei:date/@when), rview:disp-year($entry/tei:death/tei:date/@when))[. != ''], '–')
                return ($d, head($entry/tei:occupation/normalize-space()))
            case "place" return head($entry/tei:country/normalize-space())
            case "work" return head($entry/tei:author/normalize-space())
            case "event" return rview:disp-year(($entry/tei:date/@when, $entry/tei:date/@notBefore)[1])
            default return ()
    return $specific[normalize-space(.) != '']
};

(:~ One lightweight browse-list row for an entry. The mention count sits as a
 :  chip right after the entity name. :)
declare function rview:overview-row($entry as element(), $type as xs:string) {
    let $id := string($entry/@xml:id)
    let $href := rview:slug($type) || '/' || $id
    let $nInt := xs:integer(($entry/@n[. castable as xs:integer], 0)[1])
    (: authority-backed (has a Wikidata QID) entities read stronger; the OCR /
       non-reconciled long tail recedes. Mention count drives a magnitude tier
       so citation frequency is legible at a glance. :)
    let $reconciled := exists($entry/tei:idno[@type = 'wikidata'])
    let $tier := if ($nInt >= 50) then "4" else if ($nInt >= 10) then "3" else if ($nInt >= 2) then "2" else "1"
    return
        <div class="split-list-item">
            <a class="gs-entity-item gs-entity-item-{$type} {if ($reconciled) then 'gs-recon' else 'gs-unrecon'}" href="{$href}">
                <span class="gs-entity-label">{rview:entry-label($entry)}</span>
                {
                    if ($nInt > 0) then
                        <span class="gs-entity-mentions gs-m{$tier}" title="{$nInt} mention{if ($nInt > 1) then 's' else ''} dans le corpus">{$nInt}</span>
                    else ()
                }
                <span class="gs-entity-row-meta">
                    <span class="gs-entity-meta">{string-join(rview:overview-meta($entry, $type), ' · ')}</span>
                    {rview:confidence-badge(rview:confidence($entry))}
                    {rview:authority-chips($entry)}
                </span>
            </a>
        </div>
};

(:~ ---- Filters (no reindex; in-memory) ---------------------------------------
 :  Universal confidence filter + one type-specific facet (occupation for
 :  persons, country for places, language for works). The facet element name
 :  per type: :)
declare function rview:facet-name($type as xs:string) as xs:string? {
    switch($type)
        case "person" return "occupation"
        case "place" return "country"
        case "work" return "textLang"
        default return ()
};
declare function rview:facet-label($type as xs:string) as xs:string? {
    switch($type)
        case "person" return "Occupation"
        case "place" return "Pays"
        case "work" return "Langue"
        default return ()
};
declare function rview:conf-label($c as xs:string) as xs:string {
    switch($c)
        case "high" return "fiable"
        case "medium" return "moyenne"
        case "low" return "incertaine"
        case "none" return "non réconciliée"
        default return $c
};

(:~ Apply the confidence + facet filters to a set of entries. :)
declare function rview:apply-filters($entries as element()*, $type as xs:string, $conf as xs:string?, $facetVal as xs:string?) as element()* {
    let $facetName := rview:facet-name($type)
    let $byConf :=
        if ($conf and $conf != '') then
            if ($conf = 'none') then $entries[not(tei:note[@type = 'reconciliation-confidence'])]
            else $entries[tei:note[@type = 'reconciliation-confidence'] = $conf]
        else $entries
    return
        if ($facetVal and $facetVal != '' and exists($facetName)) then
            $byConf[*[local-name() = $facetName][(string(@key)[. != ''], normalize-space(.))[1] = $facetVal]]
        else
            $byConf
};

(:~ Distinct values of a child element across entries, with counts (top N). :)
declare function rview:top-facet($entries as element()*, $elem as xs:string, $limit as xs:integer) {
    let $vals := $entries/*[local-name() = $elem][normalize-space() != '' or @key]
    let $groups :=
        for $v in $vals
        let $key := (string($v/@key)[. != ''], normalize-space($v))[1]
        where $key != ''
        group by $key
        order by count($v) descending, $key
        return map { "value": $key, "label": (normalize-space($v[1]), $key)[. != ''][1], "count": count($v) }
    return subsequence($groups, 1, $limit)
};

(:~ The facet dimensions offered per type (beyond the universal confidence /
 :  authority / mentions / date filters). Each: name (query key), label, the
 :  child element to read, and which attribute holds the controlled-vocab key. :)
declare function rview:facet-defs($type as xs:string) as map(*)* {
    switch($type)
        case "person" return (
            map { "name": "occupation",  "label": "Occupation",  "elem": "occupation",  "keyAttr": "key" },
            map { "name": "nationality", "label": "Nationalité", "elem": "nationality", "keyAttr": "key" },
            map { "name": "sex",         "label": "Sexe",        "elem": "sex",         "keyAttr": "value" }
        )
        case "place" return
            map { "name": "country", "label": "Pays", "elem": "country", "keyAttr": "key" }
        case "work" return
            map { "name": "lang", "label": "Langue", "elem": "textLang", "keyAttr": "key" }
        case "event" return
            map { "name": "place", "label": "Lieu", "elem": "placeName", "keyAttr": "key" }
        case "artwork" return
            map { "name": "objtype", "label": "Type d'objet", "elem": "objectType", "keyAttr": "key" }
        default return ()
};

declare function rview:year-int($w as xs:string?) as xs:integer? {
    if (empty($w) or normalize-space($w) = '') then () else
    try {
        let $neg := starts-with($w, '-')
        let $b := if ($neg) then substring($w, 2) else $w
        let $y := xs:integer(tokenize($b, '-')[1])
        return if ($neg) then -$y else $y
    } catch * { () }
};

(:~ Representative year(s) of an entry, for date-range filtering / slider bounds. :)
declare function rview:entry-years($entry as element(), $type as xs:string) as xs:integer* {
    switch($type)
        case "person" return (rview:year-int($entry/tei:birth/tei:date/@when), rview:year-int($entry/tei:death/tei:date/@when))
        case "event" return ($entry/tei:date/(@when, @notBefore, @notAfter) ! rview:year-int(string(.)))
        default return ()
};

(:~ Distinct values of a child element across entries, with counts (top N). :)
declare function rview:top-facet-el($entries as element()*, $elem as xs:string, $keyAttr as xs:string, $limit as xs:integer) {
    let $groups :=
        for $v in $entries/*[local-name() = $elem]
        let $key := (string($v/@*[local-name() = $keyAttr])[. != ''], normalize-space($v))[1]
        where $key != ''
        group by $key
        order by count($v) descending, $key
        return map { "value": $key, "label": (normalize-space($v[1]), $key)[. != ''][1], "count": count($v) }
    (: drop the singleton long tail (mostly mis-reconciliations) to keep the
       facet list short; rare values stay reachable through free-text search :)
    return subsequence($groups[?count >= 2], 1, $limit)
};

(:~ Build all filter option lists + slider bounds for an index page. :)
declare function rview:filter-options($type as xs:string) as map(*) {
    let $all := rview:entries($type)
    let $conf :=
        (for $c in ('high', 'medium', 'low')
         let $n := count($all[tei:note[@type = 'reconciliation-confidence'] = $c])
         where $n > 0
         return map { "value": $c, "label": rview:conf-label($c), "count": $n },
         let $none := count($all[not(tei:note[@type = 'reconciliation-confidence'])])
         where $none > 0
         return map { "value": "none", "label": rview:conf-label("none"), "count": $none })
    let $facets :=
        for $d in rview:facet-defs($type)
        let $values := rview:top-facet-el($all, $d?elem, $d?keyAttr, 80)
        where exists($values)
        return map { "name": $d?name, "label": $d?label, "values": $values }
    let $years := for $e in $all return rview:entry-years($e, $type)
    let $mentions := $all/@n[. castable as xs:integer] ! xs:integer(.)
    return map {
        "confidence": $conf,
        "facets": $facets,
        "authority-count": count($all[tei:idno[@type = 'wikidata']]),
        "total": count($all),
        "has-dates": exists($years),
        "year-min": if (exists($years)) then min($years) else (),
        "year-max": if (exists($years)) then max($years) else (),
        "max-mentions": if (exists($mentions)) then max($mentions) else 0
    }
};

(:~ Parse the compact multi-facet query param: "occupation:Q1,Q2|sex:Q6581097". :)
declare function rview:parse-facets($s as xs:string?) as map(*) {
    map:merge(
        for $part in tokenize($s, '\|')[. != '']
        let $name := substring-before($part, ':')
        let $vals := tokenize(substring-after($part, ':'), ',')[. != '']
        where $name != '' and exists($vals)
        return map:entry($name, $vals)
    )
};

(:~ Faceted browse endpoint: returns filtered + sorted + paginated rows as JSON.
 :  Params: search, conf (csv), facets (compact), authority, minMentions,
 :  yearMin, yearMax, limit, offset. :)
declare function rview:browse($request as map(*)) {
    let $type := $request?parameters?type
    let $search := normalize-space($request?parameters?search)
    let $confs := tokenize($request?parameters?conf, ',')[. != '']
    let $facetSel := rview:parse-facets($request?parameters?facets)
    let $authority := $request?parameters?authority = 'true'
    let $minM := xs:integer((($request?parameters?minMentions)[. castable as xs:integer], 0)[1])
    let $yMin := ($request?parameters?yearMin)[. castable as xs:integer]
    let $yMax := ($request?parameters?yearMax)[. castable as xs:integer]
    let $limit := xs:integer((($request?parameters?limit)[. castable as xs:integer], 100)[1])
    let $offset := xs:integer((($request?parameters?offset)[. castable as xs:integer], 0)[1])
    let $defs := rview:facet-defs($type)
    let $all := rview:entries($type)
    let $r1 :=
        if ($search != '') then
            let $q := lower-case($search)
            return $all[contains(lower-case(rview:entry-label(.)), $q) or contains(rview:entry-sort(.), $q)]
        else $all
    let $r2 :=
        if (exists($confs)) then
            $r1[(let $c := rview:confidence(.) return if ($c = '') then 'none' else $c) = $confs]
        else $r1
    let $r3 :=
        fold-left(map:keys($facetSel), $r2, function($acc, $fname) {
            let $def := $defs[?name = $fname]
            return
                if (empty($def)) then $acc
                else
                    let $vals := $facetSel($fname)
                    let $elem := $def?elem
                    let $ka := ($def?keyAttr, "key")[1]
                    return $acc[some $v in *[local-name() = $elem]
                                satisfies (string($v/@*[local-name() = $ka])[. != ''], normalize-space($v))[1] = $vals]
        })
    let $r4 := if ($authority) then $r3[tei:idno[@type = 'wikidata']] else $r3
    let $r5 := if ($minM > 0) then $r4[xs:integer((@n[. castable as xs:integer], 0)[1]) >= $minM] else $r4
    let $r6 :=
        if (exists($yMin) and exists($yMax)) then
            $r5[some $y in rview:entry-years(., $type) satisfies $y >= xs:integer($yMin) and $y <= xs:integer($yMax)]
        else $r5
    let $keyed := for $e in $r6 return [rview:entry-sort($e), $e]
    let $sorted := sort($keyed, "?lang=fr-FR", function($p) { $p?1 })
    let $total := count($sorted)
    let $page := subsequence($sorted, $offset + 1, $limit)
    return map {
        "total": $total,
        "offset": $offset,
        "shown": count($page),
        "items": array { for $p in $page return rview:overview-row($p?2, $type) }
    }
};

(:~ Index page handler: renders the filter options into register-index.html. :)
declare function rview:index-html($request as map(*)) {
    vapi:html($request, map { "filters": rview:filter-options($request?parameters?type) })
};

(:~ Generic A–Z + search + filter list endpoint (pb-split-list contract). :)
declare function rview:categories($request as map(*)) {
    let $type := $request?parameters?type
    let $search := normalize-space($request?parameters?search)
    let $limit := head(($request?parameters?limit, 80))
    let $letterParam := $request?parameters?category
    let $all := rview:entries($type)
    let $searched :=
        if ($search != '') then
            let $q := lower-case($search)
            return $all[contains(lower-case(rview:entry-label(.)), $q) or contains(rview:entry-sort(.), $q)]
        else
            $all
    let $matched := rview:apply-filters($searched, $type, $request?parameters?conf, $request?parameters?facet)
    let $keyed := for $e in $matched return [rview:entry-sort($e), $e]
    let $sorted := sort($keyed, "?lang=fr-FR", function($p) { $p?1 })
    let $count := count($sorted)
    let $letter :=
        if ($count <= $limit) then "all"
        else if (empty($letterParam) or $letterParam = '') then upper-case(substring($sorted[1]?1, 1, 1))
        else $letterParam
    let $byLetter :=
        if ($letter = 'all') then $sorted
        else $sorted[starts-with(?1, lower-case($letter))]
    return
        map {
            "items": array {
                for $p in $byLetter
                return rview:overview-row($p?2, $type)
            },
            "categories":
                if ($count <= $limit) then []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count($sorted[starts-with(?1, lower-case($alpha))])
                    where $hits > 0
                    return map { "category": $alpha, "count": $hits },
                    map { "category": "all", "count": $count }
                }
        }
};

(:~ ---- Authority-file detail body (used by the generic entity template) ---- :)

declare function rview:meta-row($label as xs:string, $value) {
    if (exists($value) and (some $v in $value satisfies normalize-space(string($v)) != '')) then
        <div class="gs-meta-row"><span class="gs-meta-key">{$label}</span><span class="gs-meta-val">{$value}</span></div>
    else ()
};

declare function rview:date-disp($el as element()?) as xs:string? {
    if (empty($el)) then () else
    let $when := ($el/tei:date/@when, $el/tei:date/@notBefore, $el/tei:date/@notAfter)[1]
    let $place := $el/tei:date/tei:placeName/normalize-space()
    let $d := if ($when) then rview:disp-year($when) else normalize-space($el)
    return if ($d = '') then () else $d || (if ($place != '') then ' (' || $place || ')' else '')
};

declare function rview:authority-subhead($entry as element(), $type as xs:string) {
    let $sub :=
        switch($type)
            case "person" return string-join((rview:disp-year($entry/tei:birth/tei:date/@when), rview:disp-year($entry/tei:death/tei:date/@when))[. != ''], ' – ')
            case "place" return string-join($entry/tei:country/normalize-space(), ', ')
            default return ()
    return
        if ($sub and $sub != '') then <p class="gs-authority-sub">{$sub}</p> else ()
};

declare function rview:authority-facts($entry as element(), $type as xs:string) {
    let $rows :=
        switch($type)
            case "person" return (
                rview:meta-row("Naissance", rview:date-disp($entry/tei:birth)),
                rview:meta-row("Décès", rview:date-disp($entry/tei:death)),
                rview:meta-row("Occupations", string-join($entry/tei:occupation/normalize-space(), ', ')),
                rview:meta-row("Nationalité", string-join($entry/tei:nationality/normalize-space(), ', ')),
                rview:meta-row("Sexe", $entry/tei:sex/normalize-space())
            )
            case "place" return (
                rview:meta-row("Pays", string-join($entry/tei:country/normalize-space(), ', ')),
                rview:meta-row("Région", string-join($entry/tei:region/normalize-space(), ', ')),
                rview:meta-row("Coordonnées", $entry/tei:location/tei:geo/normalize-space())
            )
            case "work" return (
                rview:meta-row("Auteur", string-join($entry/tei:author/normalize-space(), ', ')),
                rview:meta-row("Langue", string-join($entry/tei:textLang/normalize-space(), ', '))
            )
            case "event" return (
                rview:meta-row("Date", string-join($entry/tei:date/(@when, @notBefore, @notAfter)[1] ! rview:disp-year(.), ' – ')),
                rview:meta-row("Lieu", string-join($entry/tei:placeName/normalize-space(), ', '))
            )
            case "artwork" return
                rview:meta-row("Type d'objet", string-join($entry/tei:objectType/normalize-space(), ', '))
            default return ()
    return
        if (exists($rows)) then <div class="gs-meta">{$rows}</div> else ()
};

declare function rview:authority-links-block($entry as element()) {
    let $idnos := $entry/tei:idno[normalize-space() != '']
    return
        if (empty($idnos)) then ()
        else
            <div class="gs-meta gs-authority-ids">
                <div class="gs-meta-row">
                    <span class="gs-meta-key">Référentiels</span>
                    <span class="gs-meta-val gs-auth-links">
                    {
                        for $idno in $idnos
                        let $t := string($idno/@type)
                        let $v := normalize-space($idno)
                        let $url := rview:auth-url($t, $v)
                        return
                            if (exists($url)) then
                                <a class="gs-auth-link gs-auth-{$t}" href="{$url}" target="_blank" rel="noopener">
                                    <span class="gs-auth-name">{rview:auth-abbr($t)}</span>
                                    <span class="gs-auth-id">{$v}</span>
                                    { if ($idno/@cert) then <span class="gs-auth-cert" title="indice de confiance">{string($idno/@cert)}</span> else () }
                                </a>
                            else
                                <span class="gs-auth-link">{rview:auth-abbr($t)} : {$v}</span>
                    }
                    </span>
                </div>
            </div>
};

declare function rview:provenance-block($entry as element(), $conf as xs:string) {
    let $candidates := tokenize($entry/tei:note[@type='wikidata-candidates'], '\|')[normalize-space() != '']
    let $confText := switch($conf)
        case "high" return "fiable"
        case "medium" return "moyenne"
        case "low" return "incertaine"
        default return "non réconciliée"
    return
        <div class="gs-provenance">
            <p class="gs-provenance-line">
                <span class="gs-label">Provenance</span>
                <span>Entité détectée automatiquement (NER CamemBERT + GLiNER), réconciliation Wikidata : </span>
                <span class="gs-conf-text gs-conf-{if ($conf != '') then $conf else 'none'}">{$confText}</span>
            </p>
            {
                if (exists($candidates)) then
                    <p class="gs-provenance-cands">
                        <span class="gs-label">Candidats non retenus</span>
                        {
                            for $c at $i in $candidates
                            return (
                                if ($i > 1) then <span class="gs-sep"> · </span> else (),
                                <a href="https://www.wikidata.org/wiki/{normalize-space($c)}" target="_blank" rel="noopener">{normalize-space($c)}</a>
                            )
                        }
                    </p>
                else ()
            }
        </div>
};

(:~ Full server-rendered authority file for an entry (generic across types). :)
declare function rview:detail-body($entry as element()?, $type as xs:string) {
    if (empty($entry)) then () else
    let $label := rview:entry-label($entry)
    let $conf := rview:confidence($entry)
    let $desc := normalize-space(($entry/tei:note[@type='description'], $entry/tei:desc)[1])
    let $variants :=
        distinct-values(
            for $n in $entry/(tei:persName | tei:placeName | tei:orgName | tei:title | tei:label | tei:objectName | tei:catDesc/tei:term | tei:date)
            let $s := normalize-space($n)
            where $s != '' and $s != $label and not($n/@type = 'sort')
            return $s
        )
    return
        <div class="gs-authority gs-authority-{$type}">
            <header class="gs-authority-head">
                <h1 class="gs-authority-title">{$label} {rview:confidence-badge($conf)}</h1>
                {rview:authority-subhead($entry, $type)}
            </header>
            {if ($desc != '') then <p class="gs-authority-desc">{$desc}</p> else ()}
            {
                if (exists($variants)) then
                    <p class="gs-authority-variants">
                        <span class="gs-label">Formes attestées</span>
                        {for $v in $variants return <span class="gs-variant">{$v}</span>}
                    </p>
                else ()
            }
            {rview:authority-facts($entry, $type)}
            {rview:authority-links-block($entry)}
            {rview:provenance-block($entry, $conf)}
        </div>
};

declare function rview:type-label($t as xs:string) as xs:string {
    switch($t)
        case "person" return "Personnes"
        case "place" return "Lieux"
        case "organization" return "Organisations"
        case "work" return "Œuvres"
        case "event" return "Événements"
        case "artwork" return "Objets &amp; œuvres d'art"
        case "material" return "Matériaux"
        case "technique" return "Techniques"
        case "date" return "Chronologie"
        default return $t
};

(:~ Index hub page: renders the overview grid server-side into entities.html
 :  (no client-side fetch, so the grid always appears). :)
declare function rview:hub-html($request as map(*)) {
    vapi:html($request, map { "hub": map { "cards": rview:hub-overview($request) } })
};

(:~ Index hub overview: one card per register type with total, reconciled count
 :  and most-mentioned entity. Returns HTML (server-rendered or via pb-load). :)
declare function rview:hub-overview($request as map(*)) {
    <div class="gs-hub-grid">
    {
        for $t in ("person", "place", "organization", "work", "event", "artwork", "material", "technique", "date")
        let $entries := rview:entries($t)
        let $total := count($entries)
        let $reconciled := count($entries[tei:idno[@type = 'wikidata']])
        let $nums := $entries/@n[. castable as xs:integer] ! xs:integer(.)
        let $maxN := if (exists($nums)) then max($nums) else 0
        let $top := ($entries[(@n[. castable as xs:integer], 0)[1] = $maxN])[1]
        let $exp := $t = ('date', 'artwork')
        return
            <a class="gs-hub-card gs-hub-card-{$t}" href="{$config:context-path}/{rview:slug($t)}">
                <span class="gs-hub-type">
                    <pb-i18n key="menu.{rview:slug($t)}">{rview:type-label($t)}</pb-i18n>
                    {if ($exp) then <span class="gs-exp-badge" title="Données expérimentales : OCR brut, peu ou pas réconcilié">exp.</span> else ()}
                </span>
                <span class="gs-hub-total">{$total}</span>
                <span class="gs-hub-stats">
                    <span class="gs-hub-recon">{$reconciled || ' '}<pb-i18n key="hub.reconciled">réconciliées</pb-i18n></span>
                    {if ($top and $maxN > 0) then <span class="gs-hub-top" title="Entité la plus citée du registre">{rview:entry-label($top) || ' · ' || $maxN || ' mentions'}</span> else ()}
                </span>
            </a>
    }
    </div>
};

declare function rview:places($request as map(*)){
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $limit := $request?parameters?limit
    let $odd := head(($request?parameters?odd, $config:default-odd))
    let $show-notes := $request?parameters?description = 'on'
    let $places :=
        if ($search and $search != '') then 
            collection($config:register-root)/id($config:register-map?place?id)//tei:place[ft:query(., 'name:(' || $search || '*)')]
        else
            collection($config:register-root)/id($config:register-map?place?id)//tei:place
    let $sorted := sort($places, "?lang=de-DE", function($place) { lower-case(($place/tei:placeName)[1]) })
    let $letter := 
        if (count($places) < $limit) then 
            "all"
        else if ($letterParam = '') then
            substring($sorted[1], 1, 1) => upper-case()
        else
            $letterParam
    let $byLetter :=
        if ($letter = 'all') then
            $sorted
        else
            filter($sorted, function($entry) {
                starts-with(lower-case(($entry/tei:placeName)[1]), lower-case($letter))
            })
    return
        map {
            "items": rview:output-place($byLetter, $letter, $search, $odd, $show-notes),
            "categories":
                if (count($places) < $limit) then
                    []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count(filter($sorted, function($entry) { starts-with(lower-case(($entry/tei:placeName)[1]), lower-case($alpha))}))
                    where $hits > 0
                    return
                        map {
                            "category": $alpha,
                            "count": $hits
                        },
                    map {
                        "category": "all",
                        "count": count($sorted)
                    }
                }
        }    
};

declare function rview:output-place($list, $category as xs:string, $search as xs:string?, $odd as xs:string, $show-notes as xs:boolean) {
    array {
        for $place in $list
            let $label := ($place/tei:placeName)[1]/string()
            let $id := $place/@xml:id
            let $alt := $place/tei:placeName[@type='alt']
            let $note := 
                $pm-config:web-transform($place, map { "mode": "register-overview", "show-notes": $show-notes }, $odd)
            let $coords := tokenize($place/tei:location/tei:geo)
        return
            <div class="place split-list-item">
            { $note }
            </div>
    }
};

declare function rview:places-all($request as map(*)) {
    let $places := collection($config:register-root)/id("pb-places")//tei:place
    return 
        array { 
            for $place in $places[tei:location/tei:geo/text()]
                let $geo := $place/tei:location/tei:geo
                let $coords := tokenize($geo, ' ')
                return 
                    map {
                        "latitude":$coords[1],
                        "longitude":$coords[2],
                        "label":($place/tei:placeName)[1]/string(),
                        "id": $place/@xml:id/string()
                    }
            }        
};

declare function rview:geonames-link($id) {
    let $geo := substring-after($id, 'geo-')

    return
    if ($geo) then
            <a href="https://www.geonames.org/{$geo}" target="_blank">
                w geonames
                <iron-icon icon="maps:place"/> 
            </a>      
    else 
        ()
};

declare function rview:bibliography-all($request as map(*)) {
    (: all text content is used as label :)
    let $entries := collection($config:register-root)//tei:bibl
    let $byKey := for-each($entries, function($entry as element()) {
        let $label := normalize-space($entry)
        return
            [lower-case($label), $entry]
    })
    let $sorted := rview:sort($byKey, "asc")
    return array { 
        for $entry in $sorted
        where $entry?1
        return
            map {
                "id": $entry?2/@xml:id/string(),
                "name": normalize-space($entry?2)
            }
     }
};

declare function rview:bibliography-categories($request as map(*)){
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $sortDir := ($request?parameters?dir, 'asc')[1]
    let $limit := head(($request?parameters?limit, -1))
    let $odd := head(($request?parameters?odd, $config:default-odd))
    let $entries :=
            if ($search and $search != '') then
                collection($config:register-root)/id($config:register-map?bibliography?id)//tei:bibl[ft:query(., 'name:(' || $search || '*)')]
            else
                collection($config:register-root)/id($config:register-map?bibliography?id)//tei:bibl
    let $byKey := for-each($entries, function($entry as element()) {
        let $label := normalize-space($entry)
        return
            [lower-case($label), $label, $entry]
    })
    let $sorted := rview:sort($byKey, $sortDir)
    let $letter := 
        if ($limit < 0 or count($entries) < $limit) then 
            "all"
        else if ($letterParam = '') then
            substring($sorted[1]?1, 1, 1) => upper-case()
        else
            $letterParam
    let $byLetter :=
        if ($letter = 'all') then
            $sorted
        else
            filter($sorted, function($entry) {
                starts-with($entry?1, lower-case($letter))
            })
    return
        map {
            "items": rview:output-bibliography-all($byLetter, $letter, $search, $odd),
            "categories":
                if (count($entries) < $limit) then
                    []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count(filter($sorted, function($entry) { starts-with($entry?1, lower-case($alpha))}))
                    where $hits > 0
                    return
                        map {
                            "category": $alpha,
                            "count": $hits
                        },
                    map {
                        "category": "all",
                        "count": count($sorted)
                    }
                }
        }
};

declare function rview:output-bibliography-all($list as array(*)*, $letter as xs:string,  $search as xs:string?, $odd as xs:string) {
    array {
        for $entry in $list
        let $letterParam := if ($letter = "all") then substring($entry?3/@n, 1, 1) else $letter
        let $note := 
            $pm-config:web-transform($entry?3, map { "mode": "register-overview" }, $odd)
        return
            <div class="split-list-item">
            { $note }
            </div>
    }
};