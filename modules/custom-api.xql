xquery version "3.1";

(:~
 : Custom API endpoints for the Grand Siècle project.
 : Linguistic search (lemma, POS), language-filtered queries, NER entity extraction.
 :)
module namespace api="http://teipublisher.com/api/custom";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~ Helper: resolve a document by filename in the data collection :)
declare %private function api:resolve-doc($file as xs:string) as document-node()? {
    let $collection := collection($config:data-default)
    return
        if (doc-available($config:data-default || '/' || $file)) then
            doc($config:data-default || '/' || $file)
        else
            (: try by internal ID :)
            head($collection//tei:TEI[.//tei:idno[@type='internal'] = $file]/root(.))
};

(:~
 : Keep this. This function does the actual lookup in the imported modules.
 :)
declare function api:lookup($name as xs:string, $arity as xs:integer) {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
};

(:~
 : Search by lemma across all documents, with optional language and document filters.
 : Returns word occurrences with their sentence context.
 :)
declare function api:lemma-search($request as map(*)) {
    let $query := $request?parameters?query
    let $lang := $request?parameters?lang
    let $doc := $request?parameters?doc
    let $start := ($request?parameters?start, 1)[1]
    let $per-page := ($request?parameters?per-page, 20)[1]
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    (: Find matching <w> elements by lemma :)
    let $hits :=
        for $w in $scope//tei:w[@lemma]
        where if ($query) then matches($w/@lemma, $query, 'i') else true()
        where if ($lang) then $w/ancestor-or-self::*[@xml:lang][1]/@xml:lang = $lang else true()
        return $w
    let $total := count($hits)
    let $dummy := response:set-header("X-Total", string($total))
    return
        array {
            for $hit in subsequence($hits, $start, $per-page)
            let $doc-title := root($hit)//tei:titleStmt/tei:title[1]/string()
            let $file := util:document-name(root($hit))
            (: Get sentence context if available :)
            let $sentence := $hit/ancestor::tei:s[1]
            let $context := if ($sentence) then
                    normalize-space(string-join($sentence//text(), ''))
                else
                    let $parent := ($hit/ancestor::tei:ab, $hit/ancestor::tei:note, $hit/parent::*)[1]
                    return normalize-space(substring(string-join($parent//text(), ''), 1, 200))
            return map {
                "lemma": string($hit/@lemma),
                "form": string($hit),
                "pos": string($hit/@pos),
                "msd": string($hit/@msd),
                "norm": string(($hit/@norm, '')[1]),
                "lang": string(($hit/ancestor-or-self::*[@xml:lang][1]/@xml:lang, 'unknown')[1]),
                "context": $context,
                "document": $doc-title,
                "file": $file
            }
        }
};

(:~
 : POS concordance: list all words of a given POS category in a document.
 : Groups by lemma and counts occurrences.
 :)
declare function api:pos-concordance($request as map(*)) {
    let $pos := $request?parameters?pos
    let $doc := $request?parameters?doc
    let $lang := $request?parameters?lang
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    let $words :=
        for $w in $scope//tei:w[@pos]
        where if ($pos) then $w/@pos = $pos else true()
        where if ($lang) then $w/ancestor-or-self::*[@xml:lang][1]/@xml:lang = $lang else true()
        return $w
    let $dummy := response:set-header("X-Total", string(count($words)))
    (: Group by lemma :)
    let $grouped :=
        for $w in $words
        group by $lemma := string($w/@lemma)
        let $forms := distinct-values($w/string())
        order by count($w) descending
        return map {
            "lemma": $lemma,
            "pos": string(head($w)/@pos),
            "count": count($w),
            "forms": array { $forms }
        }
    return
        array { $grouped }
};

(:~
 : List distinct POS tags found across documents, with counts.
 : Useful for populating filter dropdowns.
 :)
declare function api:pos-list($request as map(*)) {
    let $doc := $request?parameters?doc
    let $collection := collection($config:data-default)
    let $scope := if ($doc) then
            $collection//tei:TEI[.//tei:idno[@type='internal'] = $doc]/tei:text
        else
            $collection//tei:TEI/tei:text
    let $words := $scope//tei:w[@pos]
    let $grouped :=
        for $w in $words
        group by $pos := string($w/@pos)
        order by count($w) descending
        return map {
            "pos": $pos,
            "count": count($w)
        }
    return
        array { $grouped }
};

(:~
 : Extract all NER entities from a document.
 : Optional scope parameter filters mention counts to a specific reading layer:
 :   - 'original'   : mentions outside <reg> and outside marginal notes
 :   - 'modernized' : mentions outside <orig> and outside marginal notes
 :   - 'notes'      : mentions only inside <note type="MarginTextZone">
 :   - 'all' or absent : whole body (default)
 : Returns persons, places, orgs, works, events, techniques, dates, objects, materials.
 :)
declare function api:document-entities($request as map(*)) {
    let $file := $request?parameters?file
    let $scope := lower-case(($request?parameters?scope, 'all')[1])
    let $doc := api:resolve-doc($file)
    return
        if (not($doc)) then
            map { "error": "Document not found: " || $file }
        else
    let $tei := $doc//tei:TEI
    let $body := $tei/tei:text

    (: Filter a sequence of mention elements by reading-layer scope.
       Note: detect whether <reg> blocks actually contain NER mentions.
       - If yes (e.g. GLiNER has tagged entities on the modernized layer),
         'modernized' scope strictly excludes <orig> ancestors.
       - If no (typical v3 state: <reg> contains plain modernized text only),
         'modernized' shows the same entity set as 'original' so the panel
         isn't empty. :)
    let $regHasNER := exists($body//tei:reg//(tei:persName | tei:placeName | tei:orgName | tei:title[@ref] | tei:rs[@type] | tei:date[@ref] | tei:objectName | tei:material))
    let $filter-by-scope := function($mentions as element()*) as element()* {
        switch ($scope)
            case 'original' return
                $mentions[not(ancestor::tei:reg)][not(ancestor::tei:note[@type='MarginTextZone'])]
            case 'modernized' return
                (if ($regHasNER) then $mentions[not(ancestor::tei:orig)] else $mentions[not(ancestor::tei:reg)])
                    [not(ancestor::tei:note[@type='MarginTextZone'])]
            case 'notes' return
                $mentions[ancestor::tei:note[@type='MarginTextZone']]
            default return $mentions
    }

    (: --- Persons (NER-auto) --- :)
    let $persons :=
        for $p in $tei//tei:particDesc/tei:listPerson[@source='#ner-auto']/tei:person
        let $id := string($p/@xml:id)
        let $mentions := $filter-by-scope($body//tei:persName[@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "person",
            "id": $id,
            "label": normalize-space($p/tei:persName[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Places --- :)
    let $places :=
        for $p in $tei//tei:settingDesc/tei:listPlace[@source='#ner-auto']/tei:place
        let $id := string($p/@xml:id)
        let $mentions := $filter-by-scope($body//tei:placeName[@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "place",
            "id": $id,
            "label": normalize-space($p/tei:placeName[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Organizations --- :)
    let $orgs :=
        for $o in $tei//tei:particDesc/tei:listOrg[@source='#ner-auto']/tei:org
        let $id := string($o/@xml:id)
        let $mentions := $filter-by-scope($body//tei:orgName[@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "org",
            "id": $id,
            "label": normalize-space($o/tei:orgName[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Works (declared in standOff/listBibl, mentioned inline as <title ref="#work-..."/>) --- :)
    let $works :=
        for $b in $tei/tei:standOff/tei:listBibl[@source='#ner-auto']/tei:bibl
        let $id := string($b/@xml:id)
        let $mentions := $filter-by-scope($body//tei:title[@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "work",
            "id": $id,
            "label": normalize-space($b/tei:title[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Events (declared in standOff/listEvent, mentioned inline as <rs type="event" ref="#event-..."/>) --- :)
    let $events :=
        for $e in $tei/tei:standOff/tei:listEvent[@source='#ner-auto']/tei:event
        let $id := string($e/@xml:id)
        let $mentions := $filter-by-scope($body//tei:rs[@type='event'][@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "event",
            "id": $id,
            "label": normalize-space($e/tei:label[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Objects (declared in standOff/listObject, mentioned inline as <objectName ref="#..."/>) --- :)
    let $objects :=
        for $o in $tei/tei:standOff/tei:listObject[@source='#ner-auto']/tei:object
        let $id := string($o/@xml:id)
        let $mentions := $filter-by-scope($body//tei:objectName[@ref = '#' || $id])
        let $certs := $mentions/@cert/string()
        return map {
            "type": "object",
            "id": $id,
            "label": normalize-space(($o/tei:objectIdentifier/tei:objectName, $o/tei:objectName, $o/tei:label)[1]),
            "mentions": count($mentions),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Techniques (inline-only via <rs type='technique'>; group by lowercased text) --- :)
    let $tech-mentions := $filter-by-scope($body//tei:rs[@type='technique'])
    let $techniques :=
        for $label in distinct-values(for $r in $tech-mentions return lower-case(normalize-space($r)))
        let $matches := $tech-mentions[lower-case(normalize-space(.)) = $label]
        let $certs := $matches/@cert/string()
        return map {
            "type": "technique",
            "id": $label,
            "label": $label,
            "mentions": count($matches),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Dates (inline via <date @ref or @cert>; group by @ref or by text) --- :)
    let $date-mentions := $filter-by-scope($body//tei:date[@ref or @cert])
    let $dates :=
        for $key in distinct-values(for $d in $date-mentions return string(($d/@ref, normalize-space($d))[1]))
        let $matches := $date-mentions[string((@ref, normalize-space(.))[1]) = $key]
        let $certs := $matches/@cert/string()
        let $label := normalize-space($matches[1])
        return map {
            "type": "date",
            "id": replace($key, '^#', ''),
            "label": if (string-length($label) gt 0) then $label else replace($key, '^#', ''),
            "mentions": count($matches),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Materials (inline via <material @ref>; group by @ref) --- :)
    let $mat-mentions := $filter-by-scope($body//tei:material[@ref])
    let $materials :=
        for $key in distinct-values($mat-mentions/@ref/string())
        let $matches := $mat-mentions[@ref = $key]
        let $certs := $matches/@cert/string()
        let $label := normalize-space($matches[1])
        return map {
            "type": "material",
            "id": replace($key, '^#', ''),
            "label": if (string-length($label) gt 0) then $label else replace($key, '^#', ''),
            "mentions": count($matches),
            "certs": array { distinct-values($certs) },
            "source": "ner-auto"
        }

    (: --- Manual/curated persons (particDesc without @source on listPerson) --- :)
    let $manual-persons :=
        for $p in $tei//tei:particDesc[not(tei:listPerson/@source)]/tei:listPerson/tei:person
        let $id := string($p/@xml:id)
        let $mentions := $filter-by-scope($body//tei:persName[@ref = '#' || $id])
        return map {
            "type": "person",
            "id": $id,
            "label": normalize-space(string-join(($p/tei:persName/tei:forename, $p/tei:persName/tei:surname), ' ')),
            "mentions": count($mentions),
            "certs": array {},
            "source": "manual"
        }

    let $all-with-mentions := ($persons, $places, $orgs, $works, $events, $objects, $techniques, $dates, $materials, $manual-persons)
    (: Drop entities with zero mentions in the requested scope so the panel stays scoped :)
    let $all := if ($scope = 'all') then $all-with-mentions else $all-with-mentions[?mentions gt 0]

    let $summary := map {
        "document": normalize-space($tei//tei:titleStmt/tei:title[1]),
        "file": util:document-name($doc),
        "scope": $scope,
        "total-entities": count($all),
        "by-type": map {
            "person":    count($all[?type='person']),
            "place":     count($all[?type='place']),
            "org":       count($all[?type='org']),
            "work":      count($all[?type='work']),
            "event":     count($all[?type='event']),
            "object":    count($all[?type='object']),
            "technique": count($all[?type='technique']),
            "date":      count($all[?type='date']),
            "material":  count($all[?type='material'])
        }
    }

    return map {
        "summary": $summary,
        "entities": array {
            for $e in $all
            order by $e?mentions descending, $e?label
            return $e
        }
    }
};
