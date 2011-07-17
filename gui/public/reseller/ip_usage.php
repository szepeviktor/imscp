<?php
/**
 * i-MSCP a internet Multi Server Control Panel
 *
 * The contents of this file are subject to the Mozilla Public License
 * Version 1.1 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * The Original Code is "ispCP - ISP Control Panel".
 *
 * The Initial Developer of the Original Code is ispCP Team.
 * Portions created by Initial Developer are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 *
 * Portions created by the i-MSCP Team are Copyright (C) 2010 by
 * i-MSCP - internet Multi Server Control Panel. All Rights Reserved.
 *
 * @category    i-MSCP
 * @package     reseller
 * @copyright   2006-2010 by ispCP | http://isp-control.net
 * @copyright   2010-2011 by i-MSCP | http://i-mscp.net
 * @author      Klaas Tammling <klaas.tammling@st-city.net>
 * @version     SVN: $Id$
 * @link        http://i-mscp.net i-MSCP Home Site
 * @license     http://www.mozilla.org/MPL/ MPL 1.1
 * @filesource
 */

require 'imscp-lib.php';

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onResellerScriptStart);

/************************************************************************************
 * Script functions
 */

/**
 * Generate List of Domains assigned to IPs.
 *
 * @param  iMSCP_pTemplate $tpl Template engine
 * @return void
 */
function listIPDomains($tpl)
{
    global $reseller_id;

    $query = "
		SELECT
			`reseller_ips`
		FROM
			`reseller_props`
		WHERE
			`reseller_id` = ?
		;
	";

    $res = exec_query($query, $reseller_id);
    $data = $res->fetchRow();
    $reseller_ips = explode(";", substr($data['reseller_ips'], 0, -1));

    $query = "
		SELECT
			`ip_id`, `ip_number`
		FROM
			`server_ips`
		WHERE
			`ip_id`
		IN
			(" . implode(',', $reseller_ips) . ")
	";

    $rs = execute_query($query);

    if (!$rs->recordCount()) {
        while (!$rs->EOF) {

            $no_domains = false;
            $no_alias_domains = false;

            $query = "
			SELECT
				`d`.`domain_name`, `a`.`admin_name`
			FROM
				`domain` d
			INNER JOIN
				`admin` a
			ON
				(`a`.`admin_id` = `d`.`domain_created_id`)
			WHERE
				`d`.`domain_ip_id` = ?
			AND
				`d`.`domain_created_id` = ?
			ORDER BY
				`d`.`domain_name`
		";

            $rs2 = exec_query($query, array($rs->fields['ip_id'], $reseller_id));
            $domain_count = $rs2->recordCount();

            if ($rs2->recordCount() == 0) {
                $no_domains = true;
            }

            while (!$rs2->EOF) {
                $tpl->assign('DOMAIN_NAME', $rs2->fields['domain_name']);
                $tpl->parse('DOMAIN_ROW', '.domain_row');
                $rs2->moveNext();
            }

            $query = "
			    SELECT
				    `da`.`alias_name`, `a`.`admin_name`
			    FROM
				    `domain_aliasses` da
			    INNER JOIN
				    `domain` d
                ON
				    (`d`.`domain_id` = `da`.`domain_id`)
			    INNER JOIN
				    `admin` a
			    ON
				    (`a`.`admin_id` = `d`.`domain_created_id`)
			    WHERE
				    `da`.`alias_ip_id` = ?
			    AND
				    `d`.`domain_created_id` = ?
			    ORDER BY
				    `da`.`alias_name`
		";

            $rs3 = exec_query($query, array($rs->fields['ip_id'], $reseller_id));
            $alias_count = $rs3->recordCount();

            if ($rs3->recordCount() == 0) {
                $no_alias_domains = true;
            }

            while (!$rs3->EOF) {
                $tpl->assign('DOMAIN_NAME', $rs3->fields['alias_name']);
                $tpl->parse('DOMAIN_ROW', '.domain_row');
                $rs3->moveNext();
            }

            $tpl->assign(array(
                              'IP' => $rs->fields['ip_number'],
                              'RECORD_COUNT' => tr('Total Domains') . " : " . ($domain_count + $alias_count)));

            if ($no_domains && $no_alias_domains) {
                $tpl->assign(array(
                                  'DOMAIN_NAME' => tr("No records found"),
                                  'RESELLER_NAME' => ''));

                $tpl->parse('DOMAIN_ROW', '.domain_row');
            }

            $tpl->parse('IP_ROW', '.ip_row');
            $tpl->assign('DOMAIN_ROW', '');
            $rs->moveNext();
        }
    } else {
        $tpl->assign('IP_USAGE_STATISTICS', '');
        set_page_message(tr('No Ip statistics to be show.'));
    }
}

/************************************************************************************
 * Main script
 */

check_login(__FILE__);

/** @var $cfg iMSCP_Config_Handler_File */
$cfg = iMSCP_Registry::get('config');

/** @var $tpl iMSCP_pTemplate */
$tpl = new iMSCP_pTemplate();

$tpl->define_dynamic('page', $cfg->RESELLER_TEMPLATE_PATH . '/ip_usage.tpl');
$tpl->define_dynamic('ip_row', 'page');
$tpl->define_dynamic('domain_row', 'page');
$tpl->define_dynamic('logged_from', 'page');

$reseller_id = $_SESSION['user_id'];

$tpl->assign(array(
                  'TR_RESELLER_IP_USAGE_TITLE' => tr('i-MSCP - Reseller/IP Usage'),
                  'THEME_COLOR_PATH' => "../themes/{$cfg->USER_INITIAL_THEME}",
                  'THEME_CHARSET' => tr('encoding'),
                  'ISP_LOGO' => layout_getUserLogo()));

gen_reseller_mainmenu($tpl, $cfg->RESELLER_TEMPLATE_PATH . '/main_menu_statistics.tpl');
gen_reseller_menu($tpl, $cfg->RESELLER_TEMPLATE_PATH . '/menu_statistics.tpl');
gen_logged_from($tpl);

listIPDomains($tpl);

$tpl->assign(array(
                  'TR_DOMAIN_STATISTICS' => tr('Domain statistics'),
                  'TR_IP_RESELLER_USAGE_STATISTICS' => tr('Reseller/IP usage statistics'),
                  'TR_DOMAIN_NAME' => tr('Domain Name')));

generatePageMessage($tpl);

$tpl->parse('PAGE', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(
    iMSCP_Events::onResellerScriptEnd, new iMSCP_Events_Response($tpl));

$tpl->prnt();

unsetMessages();
