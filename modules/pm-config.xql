
xquery version "3.1";

module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config";

import module namespace pm-annotations-web="http://www.tei-c.org/pm/models/annotations/web/module" at "../transform/annotations-web-module.xql";
import module namespace pm-landing-web="http://www.tei-c.org/pm/models/landing/web/module" at "../transform/landing-web-module.xql";
import module namespace pm-grand_siecle-web="http://www.tei-c.org/pm/models/grand_siecle/web/module" at "../transform/grand_siecle-web-module.xql";
import module namespace pm-grand_siecle-print="http://www.tei-c.org/pm/models/grand_siecle/print/module" at "../transform/grand_siecle-print-module.xql";
import module namespace pm-grand_siecle-epub="http://www.tei-c.org/pm/models/grand_siecle/epub/module" at "../transform/grand_siecle-epub-module.xql";
import module namespace pm-teipublisher-web="http://www.tei-c.org/pm/models/teipublisher/web/module" at "../transform/teipublisher-web-module.xql";
import module namespace pm-teipublisher-print="http://www.tei-c.org/pm/models/teipublisher/print/module" at "../transform/teipublisher-print-module.xql";
import module namespace pm-teipublisher-epub="http://www.tei-c.org/pm/models/teipublisher/epub/module" at "../transform/teipublisher-epub-module.xql";

declare variable $pm-config:web-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "annotations.odd" return pm-annotations-web:transform($xml, $parameters)
case "landing.odd" return pm-landing-web:transform($xml, $parameters)
case "grand_siecle.odd" return pm-grand_siecle-web:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-web:transform($xml, $parameters)
    default return pm-grand_siecle-web:transform($xml, $parameters)
            

};
            


declare variable $pm-config:print-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "grand_siecle.odd" return pm-grand_siecle-print:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-print:transform($xml, $parameters)
    default return pm-grand_siecle-print:transform($xml, $parameters)
            

};
            


declare variable $pm-config:epub-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "grand_siecle.odd" return pm-grand_siecle-epub:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-epub:transform($xml, $parameters)
    default return pm-grand_siecle-epub:transform($xml, $parameters)
            

};
            


declare variable $pm-config:tei-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode tei")

};
            
    